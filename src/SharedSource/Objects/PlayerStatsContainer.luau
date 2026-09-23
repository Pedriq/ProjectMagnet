local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)

local PlayerStatsContainer = {}
PlayerStatsContainer.__index = PlayerStatsContainer

function PlayerStatsContainer.new()
	local self = setmetatable({}, PlayerStatsContainer)

	self.AttackRange = BaseStatsValues.AttackRange
	self.AttackCooldown = BaseStatsValues.AttacksCooldawn
	self.Capacity = BaseStatsValues.InvetoryCapacity
	self.WalkSpeed = BaseStatsValues.WalkSpeed

	return self
end

function PlayerStatsContainer:UpdateRange(level)
	self.AttackRange = self:CalculateAttackRadius(level)
	print(self)
end

function PlayerStatsContainer:UpdateAgility(level)
	self.AttackCooldown = self:CalculateAttackCooldown(level)
	print(self)
end

function PlayerStatsContainer:UpdateCapacity(level)
	self.Capacity = self:CalculateCapacity(level)
end

function PlayerStatsContainer:UpdateMobility(level)
	self.WalkSpeed = self:CalculateWalkSpeed(level)
end

function PlayerStatsContainer:CalculateAttackRadius(level)
	return BaseStatsValues.AttackRange * (1 + math.min(0.3 * level, 60) / 100)
end

function PlayerStatsContainer:CalculateAttackCooldown(level)
	local bonus = math.min(level / 100, 0.40)

	return BaseStatsValues.AttacksCooldawn * (1 - bonus)
end

function PlayerStatsContainer:CalculateCapacity(level)
	return BaseStatsValues.InvetoryCapacity + level
end

function PlayerStatsContainer:CalculateWalkSpeed(level)
	return BaseStatsValues.WalkSpeed + math.min(level, 20)
end

return PlayerStatsContainer
