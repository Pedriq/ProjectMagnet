local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local RangeScale = require(ReplicatedStorage.SharedSource.Utilities.RangeScale)

local PlayerStatsContainer = {}
PlayerStatsContainer.__index = PlayerStatsContainer

function PlayerStatsContainer.new()
	local self = setmetatable({}, PlayerStatsContainer)

	self.AttackRange = BaseStatsValues.AttackRange
	-- Кулдаун атаки фиксированный (стат Agility временно убран).
	self.AttackCooldown = BaseStatsValues.AttacksCooldawn
	self.Capacity = BaseStatsValues.InvetoryCapacity
	self.WalkSpeed = BaseStatsValues.WalkSpeed

	return self
end

function PlayerStatsContainer:UpdateRange(level)
	self.AttackRange = self:CalculateAttackRadius(level)
end

function PlayerStatsContainer:UpdateCapacity(level)
	self.Capacity = self:CalculateCapacity(level)
end

function PlayerStatsContainer:UpdateMobility(level)
	self.WalkSpeed = self:CalculateWalkSpeed(level)
end

-- Не использует self — клиент зовёт как PlayerStatsContainer:CalculateAttackCooldown()
-- (подгонка скорости анимации удара, см. RockController).
function PlayerStatsContainer:CalculateAttackCooldown()
	return BaseStatsValues.AttacksCooldawn
end

function PlayerStatsContainer:CalculateAttackRadius(level)
	local base = BaseStatsValues.AttackRange
	local multiplier = RangeScale.Multiplier(level)
	local horizontalMultiplier = RangeScale.HorizontalMultiplier(level)

	-- X и Z растут ОДНИМ множителем — хитбокс остаётся квадратным в плане на
	-- любом уровне (base.X == base.Z). Высота (Y) растёт как обычно.
	return Vector3.new(base.X * horizontalMultiplier, base.Y * multiplier, base.Z * horizontalMultiplier)
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
