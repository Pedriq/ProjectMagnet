local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local RangeScale = require(ReplicatedStorage.SharedSource.Utilities.RangeScale)

local PlayerStatsContainer = {}
PlayerStatsContainer.__index = PlayerStatsContainer

function PlayerStatsContainer.new()
	local self = setmetatable({}, PlayerStatsContainer)

	self.AttackRange = BaseStatsValues.AttackRange
	-- Фиксированный кулдаун атаки, ни от чего не зависит (ни от кликов, ни от Agility).
	self.AttackCooldown = BaseStatsValues.AttacksCooldawn
	self.Capacity = BaseStatsValues.InvetoryCapacity
	self.WalkSpeed = BaseStatsValues.WalkSpeed

	return self
end

function PlayerStatsContainer:UpdateRange(level)
	self.AttackRange = self:CalculateAttackRadius(level)
	print(self)
end

function PlayerStatsContainer:UpdateCapacity(level)
	self.Capacity = self:CalculateCapacity(level)
end

function PlayerStatsContainer:UpdateMobility(level)
	self.WalkSpeed = self:CalculateWalkSpeed(level)
end

function PlayerStatsContainer:CalculateAttackRadius(level)
	local base = BaseStatsValues.AttackRange
	local multiplier = RangeScale.Multiplier(level)
	local widthMultiplier = RangeScale.WidthMultiplier(level)
	local depthMultiplier = RangeScale.DepthMultiplier(level)

	-- X (ширина, "влево-вправо") и Z (глубина, "вперёд") растут сдержаннее полного
	-- множителя — иначе на максимуме хитбокс становится неадекватно большим.
	-- Высота (Y) растёт как обычно.
	return Vector3.new(base.X * widthMultiplier, base.Y * multiplier, base.Z * depthMultiplier)
end

-- Уровни статов начинаются с 1 (см. ProfileTemplate.Stats), поэтому на стартовом
-- уровне вместимость = базовой, каждый следующий даёт +CapacityPerLevel веса.
function PlayerStatsContainer:CalculateCapacity(level)
	return BaseStatsValues.InvetoryCapacity + (math.max(level, 1) - 1) * BaseStatsValues.CapacityPerLevel
end

function PlayerStatsContainer:CalculateWalkSpeed(level)
	return BaseStatsValues.WalkSpeed + math.min(level, 20)
end

return PlayerStatsContainer
