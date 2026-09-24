local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RockStripInitializer = {}

local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local RockGeometry = require(ReplicatedStorage.SharedSource.Object.RockGeometry)
local Strip = require(ReplicatedStorage.SharedSource.Object.Strip)
local markersFolder = workspace:WaitForChild("StripMarkers")

---- Knit Services

---- Datas

---- Assets
function RockStripInitializer:InitRockStripData()
	local strips = {}

	for _, marker in pairs(markersFolder:GetChildren()) do
		-- Section = Id руды из OreConfig.
		local section = marker:GetAttribute("Section")
		local ore = OreConfig.Get(section)

		if not ore then
			warn(
				("[RockStripInitializer] маркер %s: руды \"%s\" нет в OreConfig — полоса пропущена"):format(
					marker:GetFullName(),
					tostring(section)
				)
			)
		else
			table.insert(
				strips,
				Strip.new(
					marker.Name,
					marker.Position.X,
					marker.Position.Z,
					section,
					RockGeometry.GetMetrics(section).count,
					ore.MaxHp
				)
			)
		end
		marker:Destroy()
	end

	return strips
end

function RockStripInitializer.Start() end

function RockStripInitializer.Init() end

return RockStripInitializer
