local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local combo = require(ReplicatedStorage.ClientSource.combo)
local juice = require(ReplicatedStorage.ClientSource.juice)

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
	-- AttackHit стреляет ровно 1 раз за удар оружия (см. PlayerMagnetHitboxManager:ApplyHit).
	PlayerManagerService.AttackHit:Connect(function()
		sfx.play("Smash", { jitter = 0.08 })
	end)

	ClickerService.CritClick:Connect(function()
		sfx.play("Crit", { jitter = 0.05 })
		juice.shake(0.35)
		juice.fovPunch(3, 0.25)
	end)

	combo.Milestone:Connect(function(count)
		sfx.play("ComboUp", { pitch = 1 + count / 200 })
		juice.shake(0.25)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		if self:isClickInput(input) then
			-- ScreenGui'и эффектов рисуются с IgnoreGuiInset = true, а input.Position
			-- уже без топбара — компенсируем, чтобы попап был ровно под пальцем.
			local x, y
			if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
				local inset = GuiService:GetGuiInset()
				x, y = input.Position.X + inset.X, input.Position.Y + inset.Y
			end
			combo.register(x, y)

			-- тон клика растёт с комбо — слышно, что разгоняешься
			sfx.play("Click", { pitch = 1 + math.min(combo.count(), 60) * 0.008, jitter = 0.03 })
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
