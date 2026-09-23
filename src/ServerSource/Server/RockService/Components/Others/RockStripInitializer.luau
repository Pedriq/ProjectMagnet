local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RockStripInitializer = {}

local RockConfig = require(ReplicatedStorage.SharedSource.Datas.RockConfig)
local RockGeometry = require(ReplicatedStorage.SharedSource.Object.RockGeometry)
local Strip = require(ReplicatedStorage.SharedSource.Object.Strip)
local markersFolder = workspace:WaitForChild("StripMarkers")

---- Knit Services

---- Datas

---- Assets
function RockStripInitializer:InitRockStripData()
	local strips = {}

	for _, marker in pairs(markersFolder:GetChildren()) do
		local section = marker:GetAttribute("Section")

		table.insert(
			strips,
			Strip.new(
				marker.Name,
				marker.Position.X,
				marker.Position.Z,
				section,
				RockGeometry.GetMetrics(section).count,
				RockConfig[section].MaxHp
			)
		)
		marker:Destroy()
	end

	return strips
end

function RockStripInitializer.Start() end

function RockStripInitializer.Init() end

return RockStripInitializer
