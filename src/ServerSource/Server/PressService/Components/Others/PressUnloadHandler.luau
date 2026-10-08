local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)

--[[
	PressUnloadHandler — выгрузка руды в пресс.

	Как только HumanoidRootPart игрока оказывается внутри
	Workspace.HydraulicPress.Unloading, с игрока разом снимается ВСЯ руда
	(PlayerManagerService:TakeAllOres) и кладётся в пресс. Клиенту уходит один
	OreUnloaded со всей рудой — визуал сам решает, сколько кусочков показать в полёте.

	Unloading — Model с двумя детьми (см. PressService:GetPadParts):
	  ZoneFloor         — BasePart, ПО НЕЙ идёт детект игрока (единственная часть,
	                      которая на это влияет).
	  ZoneDashedOutline — чисто декоративная квадратная рамка (Model или
	                      BasePart), неподвижная, в детекте не участвует.
	Старый вариант (просто BasePart без вложенных ZoneFloor/ZoneDashedOutline)
	по-прежнему поддерживается — см. фолбэк в PressService:GetPadParts.
]]
local PressUnloadHandler = {}

---- Knit Services
local PressService
local PlayerManagerService

---- Datas
local TICK = 0.15
local DEBUG = false -- диагностика в Output (включать только при отладке)

---- State
local watching = false
local standing = {} -- [player] = true, пока игрок на площадке
local lastUnload = {} -- [player] = os.clock() последней выгрузки

function PressUnloadHandler:_UnloadFor(player: Player, justStepped: boolean)
	local ores = PlayerManagerService:TakeAllOres(player)
	if not ores then
		if DEBUG and justStepped then
			print("[Press] " .. player.Name .. " на Unloading, но руды нет (ни в руках, ни в profile.Ores)")
		end
		return
	end

	for oreId, weight in pairs(ores) do
		PressService:AddPressOre(player, oreId, weight)
	end
	PressService.Client.OreUnloaded:Fire(player, ores)
	lastUnload[player] = os.clock()
end

function PressUnloadHandler:_Tick()
	local onPad = PressService:GetPlayersOnPads(PressConfig.UNLOADING_NAMES)

	for player in pairs(standing) do
		if not onPad[player] then
			standing[player] = nil
		end
	end

	for player in pairs(onPad) do
		local justStepped = not standing[player]
		standing[player] = true
		if DEBUG and justStepped then
			print("[Press] " .. player.Name .. " встал на Unloading")
		end
		local ok, err = pcall(self._UnloadFor, self, player, justStepped)
		if not ok then
			warn("[PressUnloadHandler] unload failed:", err)
		end
	end
end

-- Когда с игрока последний раз выгружали руду (0 — ни разу за сессию).
-- PressCraftHandler по нему понимает, что выгрузка закончилась и можно крафтить остаток.
function PressUnloadHandler:GetLastUnloadTime(player: Player): number
	return lastUnload[player] or 0
end

-- Запускается из PressService:KnitStart().
function PressUnloadHandler:StartWatching()
	if watching then
		return
	end
	watching = true

	if DEBUG then
		task.spawn(function()
			local press = workspace:WaitForChild(PressConfig.PRESS_NAME, 10)
			if not press then
				warn("[Press] В Workspace нет модели " .. PressConfig.PRESS_NAME)
				return
			end
			local names = {}
			for _, child in ipairs(press:GetChildren()) do
				table.insert(names, child.Name .. " (" .. child.ClassName .. ")")
			end
			print("[Press] " .. PressConfig.PRESS_NAME .. " найден, дети: " .. table.concat(names, ", "))
			print("[Press] площадок Unloading (BasePart): " .. #PressService:GetPadParts(PressConfig.UNLOADING_NAMES))
			print("[Press] площадок Collect (BasePart): " .. #PressService:GetPadParts(PressConfig.COLLECT_NAMES))
		end)
	end

	task.spawn(function()
		while watching do
			task.wait(TICK)
			local ok, err = pcall(self._Tick, self)
			if not ok then
				warn("[PressUnloadHandler] tick error:", err)
			end
		end
	end)
end

function PressUnloadHandler.Start() end

function PressUnloadHandler.Init()
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerRemoving:Connect(function(player)
		standing[player] = nil
		lastUnload[player] = nil
	end)
end

return PressUnloadHandler
