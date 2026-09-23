local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local PhysicsService = game:GetService("PhysicsService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local DataCleaner = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
function DataCleaner:CleanThreads(player)
	if PlayerManagerService.PlayerThreads[player.UserId] then
		task.cancel(PlayerManagerService.PlayerThreads[player.UserId])
		PlayerManagerService.PlayerThreads[player.UserId] = nil
	end

	PlayerManagerService.PlayerThreads[player.UserId] = nil
end

function DataCleaner:CleanStats(player)
	if PlayerManagerService.PlayerStats[player.UserId] then
		PlayerManagerService.PlayerStats[player.UserId] = nil
	end
end

function DataCleaner:CleanStripData(player)
	if PlayerManagerService.PlayerStripData then
		PlayerManagerService.PlayerStripData[player.UserId] = nil
	end
end

function DataCleaner:CleanInventoryData(player)
	if PlayerManagerService.PlayersInventories then
		PlayerManagerService.PlayersInventories[player.UserId] = nil
	end
end

function DataCleaner:CleanBuffs(player)
	if PlayerManagerService.PlayerBuffs then
		PlayerManagerService.PlayerBuffs[player.UserId] = nil
	end
end

function DataCleaner:CleanLeaderstats(player)
	local connection = PlayerManagerService.LeaderstatsConnections[player.UserId]
	if connection then
		connection:Disconnect()
		PlayerManagerService.LeaderstatsConnections[player.UserId] = nil
	end
end

function DataCleaner:CleanPlayerCollisionGrooup(player)
	local charGroup = "Char_" .. player.UserId
	local rockGroup = "Rock_" .. player.UserId

	if PhysicsService:IsCollisionGroupRegistered(charGroup) then
		PhysicsService:UnregisterCollisionGroup(charGroup)
	end

	if PhysicsService:IsCollisionGroupRegistered(rockGroup) then
		PhysicsService:UnregisterCollisionGroup(rockGroup)
	end
end

function DataCleaner:CleanPlayerData(player)
	self:CleanThreads(player)
	self:CleanStats(player)
	self:CleanStripData(player)
	self:CleanPlayerCollisionGrooup(player)
	self:CleanInventoryData(player)
	self:CleanLeaderstats(player)
	self:CleanBuffs(player)
end

function DataCleaner.Start() end

function DataCleaner.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return DataCleaner
