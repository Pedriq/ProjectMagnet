local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
-- local SoundConfig = require(ReplicatedStorage.SharedSource.Datas.SoundConfig)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)

local player = Players.LocalPlayer

local PlayersRockFolder = workspace:WaitForChild("PlayersRock")

-- WaitForChild здесь стоит ДО Knit.CreateController и грузится синхронно из
-- KnitClient/init.client.luau (require всех *Controller одно за другим, до
-- Knit.Start()) — зависание тут молча блокирует загрузку ВСЕХ контроллеров
-- после этого (включая PetController). Раньше не было таймаута: если сервер
-- по гонке не успевал создать папку игрока (см. PlayerManagerService.KnitInit),
-- клиент вис навсегда без единого сообщения об этом. Теперь хотя бы громко
-- предупреждаем на каждой попытке, не переставая ждать.
local rockFolderName = tostring(player.UserId) .. "_Rock"
local PlayerRockFolder = PlayersRockFolder:FindFirstChild(rockFolderName)
while not PlayerRockFolder do
	warn("RockController: жду Workspace.PlayersRock." .. rockFolderName .. " от сервера...")
	PlayerRockFolder = PlayersRockFolder:WaitForChild(rockFolderName, 10)
end

local RockController = Knit.CreateController({
	Name = "RockController",
	VisualizedRocks = {},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
RockController.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	RockController.Components[v.Name] = require(v)
end
RockController.GetComponent = require(componentsFolder["Get()"])
RockController.SetComponent = require(componentsFolder["Set()"])

--- Knit Services
local PlayerManagerService
local RockService

--- Knit Controllers

-- Стоит ли локальный игрок сейчас в зоне майнинга, т.е. ВНУТРИ Workspace.RockZone
-- (см. RockZoneWatcher, RockService.ZoneChanged).
local inRockZone = false

function RockController:IsInRockZone(): boolean
	return inRockZone
end

function RockController:BreakSegment(segment)
	self.Components.VisualEffects:BreakSegment(segment)
end

function RockController:HitRock(model)
	self.Components.VisualEffects:HitRock(model)
	-- Анимация удара — на каждый РЕАЛЬНЫЙ автоудар сервера (HitRock фирится
	-- только своему игроку и только когда атака физически попала по камню),
	-- Кулдаун фиксированный (BaseStatsValues.RockAttackCooldown) — скорость
	-- анимации подгоняется под него.
	self.Components.RockAttackAnimation:PlayAttack(BaseStatsValues.RockAttackCooldown)
	-- Knit.GetController("SoundController"):PlaySFX(SoundConfig.HIT)
end

function RockController:UpdateRockDamage(newHp, maxHp, visualData, value)
	self.Components.RockVisualizer:UpdateRockDamage(newHp, maxHp, visualData, value)
end

function RockController:KnitStart()
	RockService.ZoneChanged:Connect(function(inZone)
		inRockZone = inZone
	end)

	PlayerManagerService.UnloadOrePiece:Connect(function(unloadingPlayer, oreName)
		self.Components.OreUnloadEffects:PlayUnload(unloadingPlayer, oreName)
	end)

	PlayerManagerService.HitRock:Connect(function(stripId, rockIndex, maxHp, newHp)
		if not stripId or not rockIndex then
			return
		end

		local rockKey = tostring(stripId) .. "_" .. tostring(rockIndex)

		local visualData = self.VisualizedRocks[rockKey]

		if not visualData then
			return
		end

		-- Эффект попадания
		self:HitRock(visualData.Model)

		-- Разрушение сегментов
		self:UpdateRockDamage(newHp, maxHp, visualData, true)
	end)
end

function RockController:KnitInit()
	componentsInitializer(script)

	PlayerManagerService = Knit.GetService("PlayerManagerService")
	RockService = Knit.GetService("RockService")
end

return RockController
