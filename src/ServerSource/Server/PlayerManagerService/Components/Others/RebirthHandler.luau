local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)
local RebirthHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
function RebirthHandler:CanRebirth(player)
	local currentLevel = PlayerManagerService:GetPlayerLevel(player)
	local rebirths = PlayerManagerService:GetPlayerRebirths(player)
	local requiredLevel = RebirthConfig.RequiredLevelForRebirth(rebirths)
	return tonumber(currentLevel) >= requiredLevel
end

function RebirthHandler:Rebirth(player)
	if not self:CanRebirth(player) then
		print("Player does not meet the requirements to rebirth.")
		return
	end

	local playerRebirths = PlayerManagerService:GetPlayerRebirths(player)

	playerRebirths += 1

	PlayerManagerService:ChangePlayerLevel(player, 1)
	PlayerManagerService:ChangePlayerMagnetism(player, 0)
	PlayerManagerService:ChangePlayerRebirths(player, playerRebirths)
	PlayerManagerService:ChangePlayerCashMultiplier(player, 1 + playerRebirths * RebirthConfig.CashMultiplierPerRebirth)
	PlayerManagerService:ChangePlayerMagnetismMultiplier(
		player,
		1 + playerRebirths * RebirthConfig.MagnetismMultiplierPerRebirth
	)
end

function RebirthHandler.Start() end

function RebirthHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return RebirthHandler
