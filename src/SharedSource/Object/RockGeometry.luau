local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local RockGeometry = {}

-- Length (Z) of a StripMarker; a strip's rocks are laid out along this span.
local ROW_WIDTH = 58
-- Small breathing room between neighboring rocks so the row doesn't read as fused together.
local ROCK_GAP = 0.3
-- World Y of the ground a strip sits on: the top face of the Selection pads.
-- Rock hitboxes rest their bottom face here (StripMarker Y varies and isn't reliable).
local GROUND_Y = -1

local rockTemplates = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Rock")
local cache = {}

-- Per-section metrics (hitbox size, spacing, how many fit in a strip),
-- derived from that section's model so resizing/rebalancing a model in
-- ReplicatedStorage.Assets.Rock doesn't require touching any code.
function RockGeometry.GetMetrics(section)
	local cached = cache[section]

	if cached then
		return cached
	end

	-- Имя модели руды берётся из OreConfig (section = OreConfig Id).
	local ore = OreConfig.Get(section)
	local template = ore and rockTemplates:FindFirstChild(ore.Model)

	if not template then
		error("RockGeometry: no rock model found for section " .. tostring(section))
	end

	local boundingCFrame, size = template:GetBoundingBox()

	local spacing = size.Z + ROCK_GAP
	local count = math.floor(ROW_WIDTH / spacing) + 1

	-- The model's authored pivot isn't necessarily at its geometric bottom,
	-- so track the offset to keep the model from sinking into/floating above the hitbox.
	local pivot = template:GetPivot()
	local boundingBottomY = boundingCFrame.Position.Y - size.Y / 2
	local pivotToBottom = pivot.Position.Y - boundingBottomY

	local metrics = {
		hitboxSize = size,
		spacing = spacing,
		count = count,
		pivotToBottom = pivotToBottom,
	}

	cache[section] = metrics

	return metrics
end

function RockGeometry.GetRowWidth()
	return ROW_WIDTH
end

function RockGeometry.GetGroundY()
	return GROUND_Y
end

return RockGeometry
