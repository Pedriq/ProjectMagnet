local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local perf = require(ReplicatedStorage.ClientSource.perf)

local player = Players.LocalPlayer

local PlayersRockFolder = workspace:WaitForChild("PlayersRock")

-- WaitForChild здесь стоит ДО Knit.CreateController и грузится синхронно из
-- KnitClient/init.client.luau (require всех *Controller одно за другим, до
-- Knit.Start()) — зависание тут молча блокирует загрузку ВСЕХ контроллеров
-- после этого. Раньше не было таймаута: если сервер
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

--- Knit Controllers

function RockController:BreakSegment(segment)
	self.Components.VisualEffects:BreakSegment(segment)
end

function RockController:HitRock(model)
	self.Components.VisualEffects:HitRock(model)
	-- Анимации взмаха персонажа при ударе по камню нет (убрана): остаются эффект на камне и звук.
	-- RockAttackAnimation по-прежнему используется автоклик-зонами (AutoClickZoneController).
	sfx.play("Hit", { jitter = 0.1 })
end

function RockController:UpdateRockDamage(newHp, maxHp, visualData, value)
	self.Components.RockVisualizer:UpdateRockDamage(newHp, maxHp, visualData, value)
end

function RockController:KnitStart()
	PlayerManagerService.HitRocks:Connect(function(hits)
		if type(hits) ~= "table" then
			return
		end
		for _, hit in ipairs(hits) do
			self:_OnRockHit(hit[1], hit[2], hit[3], hit[4])
		end
	end)
end

function RockController:_OnRockHit(stripId, rockIndex, maxHp, newHp)
	if not stripId or not rockIndex then
		return
	end

	local rockKey = tostring(stripId) .. "_" .. tostring(rockIndex)

	local visualData = self.VisualizedRocks[rockKey]

	if not visualData then
		return
	end

	-- Камень добит: сразу убираем коллизию хитбокса ЛОКАЛЬНО. Сервер и так
	-- удалит хитбокс, но удаление долетает только через пинг, а персонаж
	-- симулируется у клиента — без этого игрок успевает «споткнуться» о
	-- невидимый хитбокс уже разбитого камня. Один раз по событию, без опроса.
	if newHp <= 0 then
		local hitbox = visualData.Hitbox
		if hitbox and hitbox.Parent then
			hitbox.CanCollide = false
		end
	end

	-- Эффект попадания. На мобильных на добивающем ударе пропускаем тряску/вспышку:
	-- модель тут же рассыпается (ShatterRock), лишние tween'ы только жгут кадр.
	if not (perf.isMobile and newHp <= 0) then
		self:HitRock(visualData.Model)
	end

	-- Цифра урона, полоска HP, искры, тряска; на добивании — взрыв
	self.Components.HitFeedback:OnHit(visualData, maxHp, newHp)

	-- Разрушение сегментов
	self:UpdateRockDamage(newHp, maxHp, visualData, true)
end

function RockController:KnitInit()
	componentsInitializer(script)

	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return RockController
