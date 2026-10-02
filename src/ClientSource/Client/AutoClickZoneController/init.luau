local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local AutoClickZoneController = Knit.CreateController({
	Name = "AutoClickZoneController",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
AutoClickZoneController.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	AutoClickZoneController.Components[v.Name] = require(v)
end
AutoClickZoneController.GetComponent = require(componentsFolder["Get()"])
AutoClickZoneController.SetComponent = require(componentsFolder["Set()"])

--- Knit Services
local AutoClickZoneService

--- Knit Controllers
local RockController

function AutoClickZoneController:KnitStart()
	-- Визуальная пульсация катушки Теслы зоны при успешном автоклике (см. ZonePulseEffect).
	-- Показ ShowMessage ("Not enough rebirths" и т.п.) — отдельно, в
	-- UI.components.FeedbackOverlay (нижние подсказки, pushNotice).
	AutoClickZoneService.ZonePulse:Connect(function(teslaCoil)
		sfx.play("Click")
		if teslaCoil then
			sfx.play("Hit")
		end
		self.Components.ZonePulseEffect:Pulse(teslaCoil)

		-- Тот же свинг оружия, что и на обычном ударе по камню (см.
		-- RockController:HitRock) — сервер сам анимацию не проигрывает
		-- (AutoClickZoneHandler), это исключительно клиентская логика.
		RockController.Components.RockAttackAnimation:PlayAttack()
	end)
end

function AutoClickZoneController:KnitInit()
	componentsInitializer(script)

	AutoClickZoneService = Knit.GetService("AutoClickZoneService")
	RockController = Knit.GetController("RockController")
end

return AutoClickZoneController
