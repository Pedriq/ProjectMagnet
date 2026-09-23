local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local ClickerService = Knit.CreateService({
	Name = "ClickerService",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
ClickerService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	ClickerService.Components[v.Name] = require(v)
end
ClickerService.GetComponent = require(componentsFolder["Get()"])
ClickerService.SetComponent = require(componentsFolder["Set()"])

---- Knit Services
local PlayerManagerService
local ProfileService

function ClickerService.Client:Click(player)
	-- TODO add debaounce
	self.Server.Components.ClickHandler:Click(player)
end

-- Серверный клик от имени игрока с доп. множителем (например, AutoClickZone).
-- Переиспользует ту же логику начисления силы, что и обычный клик игрока.
function ClickerService:Click(player, multiplier: number?)
	self.Components.ClickHandler:Click(player, multiplier)
end

function ClickerService:GetPlayerMagnetism(player)
	return ProfileService:GetData(player, { "Stats", "Magnetism" })
end

function ClickerService:ChangePlayerMagnetism(player, magnetism)
	return ProfileService:ChangeData(player, { "Stats", "Magnetism" }, magnetism)
end

function ClickerService:GetPlayerLevel(player)
	return ProfileService:GetData(player, { "Stats", "Level" })
end

function ClickerService:ChangePlayerLevel(player, level)
	ProfileService:ChangeData(player, { "Stats", "Level" }, level)
end

function ClickerService:KnitStart() end

function ClickerService:KnitInit()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)
end

return ClickerService
