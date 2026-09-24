local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	PressController — клиентская часть гидравлического пресса (см. PressService).
	Сервер шлёт сигналы только игроку, который пользуется прессом, а весь визуал
	(PressVisualizer) создаётся локально — другие игроки его не видят.
]]
local PressController = Knit.CreateController({
	Name = "PressController",
	-- руда в прессе (зеркало profile.Press.Ores): map[oreId] = вес
	PressOres = {},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
PressController.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	PressController.Components[v.Name] = require(v)
end
PressController.GetComponent = require(componentsFolder["Get()"])
PressController.SetComponent = require(componentsFolder["Set()"])

--- Knit Services
local PressService
local ProfileService

---- Datas
local PRESS_NAME = "HydraulicPress"

function PressController:_SetOre(oreId, weight)
	self.PressOres[oreId] = if type(weight) == "number" and weight > 0 then weight else nil
	self.Components.PressVisualizer:UpdateProgress(self.PressOres)
end

function PressController:KnitStart()
	local visualizer = self.Components.PressVisualizer

	PressService.OreUnloaded:Connect(function(oreId)
		visualizer:OreUnloaded(oreId)
	end)

	PressService.ItemCrafted:Connect(function(oreId, weight, itemName, rarity, payout)
		visualizer:ItemCrafted(oreId, weight, itemName, rarity, payout)
	end)

	ProfileService.UpdateSpecificData:Connect(function(path, value)
		if path[1] == "Press" and path[2] == "Ores" and path[3] ~= nil then
			self:_SetOre(path[3], value)
		end
	end)

	task.spawn(function()
		local press = workspace:WaitForChild(PRESS_NAME, 30)
		if not press then
			warn("PressController: не найден Workspace." .. PRESS_NAME)
			return
		end
		visualizer:Setup(press)

		PressService:GetState()
			:andThen(function(state)
				if type(state) ~= "table" or type(state.Ores) ~= "table" then
					return
				end
				for oreId, weight in pairs(state.Ores) do
					self.PressOres[oreId] = weight
				end
				visualizer:BuildPile(state.Ores)
				visualizer:UpdateProgress(self.PressOres)
			end)
			:catch(warn)
	end)
end

function PressController:KnitInit()
	componentsInitializer(script)

	PressService = Knit.GetService("PressService")
	ProfileService = Knit.GetService("ProfileService")
end

return PressController
