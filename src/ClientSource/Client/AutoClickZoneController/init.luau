local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local juice = require(ReplicatedStorage.ClientSource.juice)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

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

-- Всплывающее число прироста силы за автоклик — тот же juice.worldText и тот же стиль
-- (белый с лёгкой подкраской, «поп» + всплытие), что у чисел урона по камню
-- (RockController.HitFeedback), только цвет силы и знак «+».
function AutoClickZoneController:ShowGain(gain)
	if gain == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	juice.worldText(
		hrp.Position + Vector3.new(0, 3.2, 0),
		"+" .. Format.short(gain),
		Color3.new(1, 1, 1):Lerp(Theme.ElectricBright, 0.35),
		{ size = 1.1, rise = 2.2 }
	)
end

function AutoClickZoneController:KnitStart()
	-- Визуальная пульсация катушки Теслы зоны при успешном автоклике (см. ZonePulseEffect).
	-- Показ ShowMessage ("Not enough rebirths" и т.п.) — отдельно, в
	-- UI.components.FeedbackOverlay (нижние подсказки, pushNotice).
	AutoClickZoneService.ZonePulse:Connect(function(teslaCoil, gain)
		self:ShowGain(gain)
		sfx.play("Click")
		if teslaCoil then
			sfx.play("Hit")
		end
		self.Components.ZonePulseEffect:Pulse(teslaCoil)
	end)
end

function AutoClickZoneController:KnitInit()
	componentsInitializer(script)

	AutoClickZoneService = Knit.GetService("AutoClickZoneService")
end

return AutoClickZoneController
