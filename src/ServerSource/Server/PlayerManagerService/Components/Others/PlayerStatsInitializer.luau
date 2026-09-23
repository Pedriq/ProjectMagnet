local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerStatsContainer = require(ReplicatedStorage.SharedSource.Object.PlayerStatsContainer)
local PlayerStatsInitializer = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
function PlayerStatsInitializer:InitPlayerStats(player)
	local stats = PlayerStatsContainer.new()

	player:SetAttribute("RangeLevel", PlayerManagerService:GetPlayerRange(player))

	player:SetAttribute("AgilityLevel", PlayerManagerService:GetPlayerAgility(player))

	player:SetAttribute("CapacityLevel", PlayerManagerService:GetPlayerCapacity(player))

	player:SetAttribute("MobilityLevel", PlayerManagerService:GetPlayerMobility(player))

	stats:UpdateRange(player:GetAttribute("RangeLevel"))

	stats:UpdateCapacity(player:GetAttribute("CapacityLevel"))

	stats:UpdateMobility(player:GetAttribute("MobilityLevel"))

	-- listeners
	player:GetAttributeChangedSignal("RangeLevel"):Connect(function()
		stats:UpdateRange(player:GetAttribute("RangeLevel"))

		PlayerManagerService:CreateWeaponHitbox(player)
		-- пересоздаёт модель оружия с масштабом под новый уровень (RangeScale.Multiplier)
		PlayerManagerService:GiveWeapon(player)
	end)

	player:GetAttributeChangedSignal("CapacityLevel"):Connect(function()
		stats:UpdateCapacity(player:GetAttribute("CapacityLevel"))
		PlayerManagerService:PushCarryInfo(player)
	end)

	player:GetAttributeChangedSignal("MobilityLevel"):Connect(function()
		stats:UpdateMobility(player:GetAttribute("MobilityLevel"))

		PlayerManagerService:ApplyWalkSpeed(player)
	end)

	PlayerManagerService.PlayerStats[player.UserId] = stats
end

function PlayerStatsInitializer.Start() end

function PlayerStatsInitializer.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PlayerStatsInitializer
