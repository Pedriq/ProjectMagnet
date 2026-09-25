local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)

--[[
	PressCollectHandler — сбор денег за проданные прессом предметы.

	PressCraftHandler не зачисляет деньги сразу, а копит их в
	profile.Press.Unclaimed. Пока HumanoidRootPart игрока над
	Workspace.HydraulicPress.Collect (см. PressConfig.COLLECT_NAMES), накопленное
	переносится в Stats.Money, а клиенту уходит MoneyCollected.
]]
local PressCollectHandler = {}

---- Knit Services
local PressService
local PlayerManagerService

---- Datas
local TICK = 0.1

---- State
local watching = false

function PressCollectHandler:_CollectFor(player: Player)
	local unclaimed = PressService:GetUnclaimed(player)
	if not EtNum.me(unclaimed, "0") then
		return
	end

	local money = PlayerManagerService:GetPlayerMoney(player)
	if not money then
		return
	end

	PressService:SetUnclaimed(player, "0")
	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.add(unclaimed, money)))
	-- unclaimed уже EtNum-строка из профиля (EtNum.toString принимает только EtNum-объект)
	PressService.Client.MoneyCollected:Fire(player, unclaimed)
end

function PressCollectHandler:_Tick()
	for player in pairs(PressService:GetPlayersOnPads(PressConfig.COLLECT_NAMES)) do
		local ok, err = pcall(self._CollectFor, self, player)
		if not ok then
			warn("[PressCollectHandler] collect failed:", err)
		end
	end
end

-- Запускается из PressService:KnitStart().
function PressCollectHandler:StartWatching()
	if watching then
		return
	end
	watching = true

	task.spawn(function()
		while watching do
			task.wait(TICK)
			local ok, err = pcall(self._Tick, self)
			if not ok then
				warn("[PressCollectHandler] tick error:", err)
			end
		end
	end)
end

function PressCollectHandler.Start() end

function PressCollectHandler.Init()
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PressCollectHandler
