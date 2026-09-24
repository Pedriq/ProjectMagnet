local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)

--[[
	PressUnloadHandler — выгрузка руды в пресс.

	Пока HumanoidRootPart игрока внутри Workspace.HydraulicPress.Unloading
	(BasePart или Model; таких детей может быть несколько), раз в
	PressConfig.GetUnloadInterval(UnloadSpeed) с игрока снимается один кусочек
	руды (PlayerManagerService:TakeOrePiece) и кладётся в пресс.
]]
local PressUnloadHandler = {}

---- Knit Services
local PressService
local PlayerManagerService

---- Datas
local PRESS_NAME = "HydraulicPress"
local UNLOADING_NAME = "Unloading"
local TICK = 0.05
-- Не больше стольких кусочков за тик (на случай лага сервера).
local MAX_PIECES_PER_TICK = 10
-- Высота зоны над площадкой, в которой должен оказаться HumanoidRootPart.
local PAD_CHECK_HEIGHT = 8
local DEBUG = true -- диагностика в Output (выключить, когда всё заработает)

---- State
local watching = false
local accumulators = {} -- [player] = секунд на площадке, ещё не «потраченных» на кусочки
local lastUnload = {} -- [player] = os.clock() последнего выгруженного кусочка

-- Все BasePart'ы площадок выгрузки.
local function getUnloadingParts(): { BasePart }
	local press = workspace:FindFirstChild(PRESS_NAME)
	local parts = {}
	if not press then
		return parts
	end

	for _, child in ipairs(press:GetChildren()) do
		if child.Name == UNLOADING_NAME then
			if child:IsA("BasePart") then
				table.insert(parts, child)
			else
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(parts, d)
					end
				end
			end
		end
	end
	return parts
end

-- Игроки (с загруженным профилем), чей HumanoidRootPart сейчас на площадке.
local function getPlayersOnPad(): { [Player]: boolean }
	local onPad = {}
	local pads = getUnloadingParts()
	if #pads == 0 then
		return onPad
	end

	local roots = {}
	local rootToPlayer = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and PressService:IsProfileLoaded(player) then
			table.insert(roots, root)
			rootToPlayer[root] = player
		end
	end
	if #roots == 0 then
		return onPad
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots

	for _, pad in ipairs(pads) do
		-- Unloading обычно плоская плита на полу, а HumanoidRootPart висит ~3 studs
		-- над ней и с самой плитой не пересекается — поэтому проверяем объём,
		-- вытянутый вверх от плиты на PAD_CHECK_HEIGHT.
		local boxCFrame = pad.CFrame * CFrame.new(0, PAD_CHECK_HEIGHT / 2, 0)
		local boxSize = Vector3.new(pad.Size.X, pad.Size.Y + PAD_CHECK_HEIGHT, pad.Size.Z)
		for _, part in ipairs(workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)) do
			local player = rootToPlayer[part]
			if player then
				onPad[player] = true
			end
		end
	end
	return onPad
end

function PressUnloadHandler:_UnloadFor(player: Player, dt: number)
	local interval = PressConfig.GetUnloadInterval(PressService:GetPressLevel(player, "UnloadSpeed"))
	local acc = (accumulators[player] or 0) + dt
	local pieces = 0

	while acc >= interval and pieces < MAX_PIECES_PER_TICK do
		local oreId, weight = PlayerManagerService:TakeOrePiece(player)
		if not oreId then
			if DEBUG and accumulators[player] == nil then
				print("[Press] " .. player.Name .. " на Unloading, но руды нет (ни в руках, ни в profile.Ores)")
			end
			acc = 0
			break
		end

		PressService:AddPressOre(player, oreId, weight)
		PressService.Client.OreUnloaded:Fire(player, oreId, weight)
		lastUnload[player] = os.clock()

		acc -= interval
		pieces += 1
	end

	accumulators[player] = math.min(acc, interval)
end

function PressUnloadHandler:_Tick(dt: number)
	local onPad = getPlayersOnPad()

	for player in pairs(accumulators) do
		if not onPad[player] then
			accumulators[player] = nil
		end
	end

	for player in pairs(onPad) do
		if DEBUG and accumulators[player] == nil then
			print("[Press] " .. player.Name .. " встал на Unloading")
		end
		local ok, err = pcall(self._UnloadFor, self, player, dt)
		if not ok then
			warn("[PressUnloadHandler] unload failed:", err)
		end
	end
end

-- Когда с игрока последний раз выгрузили кусочек (0 — ни разу за сессию).
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
			local press = workspace:WaitForChild(PRESS_NAME, 10)
			if not press then
				warn("[Press] В Workspace нет модели " .. PRESS_NAME)
				return
			end
			local names = {}
			for _, child in ipairs(press:GetChildren()) do
				table.insert(names, child.Name .. " (" .. child.ClassName .. ")")
			end
			print("[Press] " .. PRESS_NAME .. " найден, дети: " .. table.concat(names, ", "))
			print("[Press] площадок Unloading (BasePart): " .. #getUnloadingParts())
		end)
	end

	task.spawn(function()
		local last = os.clock()
		while watching do
			task.wait(TICK)
			local now = os.clock()
			local ok, err = pcall(self._Tick, self, now - last)
			if not ok then
				warn("[PressUnloadHandler] tick error:", err)
			end
			last = now
		end
	end)
end

function PressUnloadHandler.Start() end

function PressUnloadHandler.Init()
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerRemoving:Connect(function(player)
		accumulators[player] = nil
		lastUnload[player] = nil
	end)
end

return PressUnloadHandler
