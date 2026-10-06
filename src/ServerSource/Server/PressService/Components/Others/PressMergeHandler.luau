local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local PressMergeConfig = require(ReplicatedStorage.SharedSource.Datas.PressMergeConfig)

--[[
	PressMergeHandler — площадка Merge у пресса (Workspace.HydraulicPress.Merge).

	Когда HumanoidRootPart игрока оказывается над площадкой (тот же детект, что у Unloading /
	Collect, см. PressService:GetPlayersOnPads), запускается Ore Merge «всей очереди»
	(PressService:MergeOres(player, nil) — снизу вверх, по текущим правилам и ratio игрока).

	  * есть что объединять — merge + эффект (сигнал PressService.OreMerged);
	  * нечего — эффекта нет, игроку уходит уведомление (PressService.Notice).

	Надёжность: срабатывание по ВХОДУ на площадку — пока игрок стоит, повторов нет; чтобы снова
	сработать, нужно сойти с площадки. Дополнительно — кулдаун COOLDOWN после срабатывания, чтобы
	дрожание на границе площадки (вышел-вошёл за доли секунды) не запускало merge повторно.
]]
local PressMergeHandler = {}

---- Knit Services
local PressService

---- Datas
local TICK = 0.1
local COOLDOWN = 1.0 -- секунд между срабатываниями у одного игрока

---- State
local watching = false
local standing = {} -- [player] = true, пока игрок на площадке
local lastTrigger = {} -- [player] = os.clock() последнего срабатывания

function PressMergeHandler:_Trigger(player: Player)
	if PressService:MergeOres(player, nil) then
		return
	end

	local ratio = PressMergeConfig.RatioText(PressService:GetMergeLevel(player))
	PressService.Client.Notice:Fire(player, "Nothing to merge", `You need {ratio} of the same ore`)
end

function PressMergeHandler:_Tick()
	local onPad = PressService:GetPlayersOnPads(PressConfig.MERGE_NAMES)

	for player in pairs(standing) do
		if not onPad[player] then
			standing[player] = nil
		end
	end

	local now = os.clock()
	for player in pairs(onPad) do
		if not standing[player] then
			standing[player] = true -- до вызова: даже при ошибке не повторяем, пока игрок стоит
			if now - (lastTrigger[player] or 0) >= COOLDOWN then
				lastTrigger[player] = now
				local ok, err = pcall(self._Trigger, self, player)
				if not ok then
					warn("[PressMergeHandler] merge failed:", err)
				end
			end
		end
	end
end

-- Запускается из PressService:KnitStart().
function PressMergeHandler:StartWatching()
	if watching then
		return
	end
	watching = true

	task.spawn(function()
		while watching do
			task.wait(TICK)
			local ok, err = pcall(self._Tick, self)
			if not ok then
				warn("[PressMergeHandler] tick error:", err)
			end
		end
	end)
end

function PressMergeHandler.Start() end

function PressMergeHandler.Init()
	PressService = Knit.GetService("PressService")

	Players.PlayerRemoving:Connect(function(player)
		standing[player] = nil
		lastTrigger[player] = nil
	end)
end

return PressMergeHandler
