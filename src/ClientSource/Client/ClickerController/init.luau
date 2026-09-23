local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local ClickerController = Knit.CreateController({
	Name = "ClickerController",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
ClickerController.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	ClickerController.Components[v.Name] = require(v)
end
ClickerController.GetComponent = require(componentsFolder["Get()"])
ClickerController.SetComponent = require(componentsFolder["Set()"])

--- Knit Services
local ClickerService
local PlayerManagerService

--- Knit Controllers
function ClickerController:isClickInput(input)
	return self.Components.ClickCheck:isClickInput(input)
end

function ClickerController:KnitStart()
	-- AttackHit стреляет ровно 1 раз за удар оружия (см. PlayerWeaponHitboxManager:ApplyHit).
	PlayerManagerService.AttackHit:Connect(function()
		sfx.play("Smash")
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		if self:isClickInput(input) then
			sfx.play("Click")
			ClickerService:Click(Players.LocalPlayer)
		end
	end)
end

function ClickerController:KnitInit()
	ClickerService = Knit.GetService("ClickerService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	componentsInitializer(script)
end

return ClickerController
