local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerStripDataInitializer = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
function PlayerStripDataInitializer:InitStripDataForPlayer(player)
	local stripData = PlayerManagerService:GetStripData()

	PlayerManagerService.PlayerStripData[player.UserId] = {}

	for _, strip in pairs(stripData) do
		PlayerManagerService.PlayerStripData[player.UserId][strip.stripId] = {}
		for rockIndex = 1, strip.rockCount do
			PlayerManagerService.PlayerStripData[player.UserId][strip.stripId][rockIndex] =
				{ hp = strip.rockMaxHp, cut = false }
		end
	end
end

function PlayerStripDataInitializer.Start() end

function PlayerStripDataInitializer.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PlayerStripDataInitializer
