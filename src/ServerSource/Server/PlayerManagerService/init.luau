local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local PlayerManagerService = Knit.CreateService({
	Name = "PlayerManagerService",
	PlayerStripData = {},
	PlayerThreads = {},
	PlayerStats = {},
	PlayersInventories = {},
	Client = {
		HitRock = Knit.CreateSignal(),
		-- FireAll(player, oreName) — один кусочек руды улетел из игрока в пресс
		-- (см. PlayerOresManager, клиентский OreUnloadEffects).
		UnloadOrePiece = Knit.CreateSignal(),
	},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
PlayerManagerService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	PlayerManagerService.Components[v.Name] = require(v)
end
PlayerManagerService.GetComponent = require(componentsFolder["Get()"])
PlayerManagerService.SetComponent = require(componentsFolder["Set()"])

---- Knit Services
local RockService
local ProfileService

function PlayerManagerService:GetStripData()
	return RockService:GetStripData()
end

function PlayerManagerService:GetRockState(userId, stripId, rockIndex)
	local playerData = self.PlayerStripData[userId]
	local stripData = playerData and playerData[stripId]

	return stripData and stripData[rockIndex]
end

function PlayerManagerService:ChangeWeapon(player, weaponData)
	ProfileService:ChangeData(player, { "Weapon" }, weaponData)
end

function PlayerManagerService:ChangePlayerMoney(player, money)
	ProfileService:ChangeData(player, { "Stats", "Money" }, money)
end

function PlayerManagerService:GetAllPlayerData(player)
	local _, playerData = ProfileService:GetProfile(player)

	return playerData
end

function PlayerManagerService:GetPlayerItems(player)
	local _, playerData = ProfileService:GetProfile(player)

	return playerData.Items
end

function PlayerManagerService:GetPlayerItem(player, itemId)
	local _, playerData = ProfileService:GetProfile(player)

	if playerData.Items[itemId] then
		return playerData.Items[itemId]
	end

	return nil
end

function PlayerManagerService:GetPlayerWeapon(player)
	return ProfileService:GetData(player, { "Weapon" })
end

function PlayerManagerService:ChangePlayerStrength(player, strength)
	ProfileService:ChangeData(player, { "Stats", "Strength" }, strength)
end

function PlayerManagerService:GetPlayerCashMultiplier(player)
	return ProfileService:GetData(player, { "Multipliers", "Cash" })
end

function PlayerManagerService:ChangePlayerCashMultiplier(player, multiplier)
	ProfileService:ChangeData(player, { "Multipliers", "Cash" }, multiplier)
end

function PlayerManagerService:GetPlayerStrengthMultiplier(player)
	return ProfileService:GetData(player, { "Multipliers", "Strength" })
end

function PlayerManagerService:ChangePlayerStrengthMultiplier(player, multiplier)
	ProfileService:ChangeData(player, { "Multipliers", "Strength" }, multiplier)
end

function PlayerManagerService:GetPlayerRebirths(player)
	return ProfileService:GetData(player, { "Stats", "Rebirth" })
end

function PlayerManagerService:ChangePlayerRebirths(player, rebirths)
	ProfileService:ChangeData(player, { "Stats", "Rebirth" }, rebirths)
end

function PlayerManagerService:GetPlayerLevel(player)
	return ProfileService:GetData(player, { "Progress", "Level" })
end

function PlayerManagerService:GetPlayerFat(player)
	return ProfileService:GetData(player, { "Progress", "Fat" })
end

function PlayerManagerService:ChangePlayerLevel(player, level)
	ProfileService:ChangeData(player, { "Stats", "Level" }, level)
end

function PlayerManagerService:GetPlayerMoney(player)
	return ProfileService:GetData(player, { "Stats", "Money" })
end

function PlayerManagerService:GetPlayerRange(player)
	return ProfileService:GetData(player, { "Stats", "Range" })
end

function PlayerManagerService:GetPlayerAgility(player)
	return ProfileService:GetData(player, { "Stats", "Agility" })
end

function PlayerManagerService:GetPlayerCapacity(player)
	return ProfileService:GetData(player, { "Stats", "Capacity" })
end

function PlayerManagerService:GetPlayerMobility(player)
	return ProfileService:GetData(player, { "Stats", "Mobility" })
end

function PlayerManagerService:GetPlayerOres(player)
	return ProfileService:GetData(player, { "Ores" })
end

function PlayerManagerService:ChangePlayerOres(player, ores)
	ProfileService:ChangeData(player, { "Ores" }, ores)
end

function PlayerManagerService:AddOrePieces(player, oreName, pieces)
	self.Components.PlayerOresManager:AddOrePieces(player, oreName, pieces)
end

function PlayerManagerService:GetPlayerStatsValues(player)
	return self.PlayerStats[player.UserId]
end

function PlayerManagerService:CreateWeaponHitbox(player)
	self.Components.PlayerWeaponHitboxManager:CreateWeaponHitbox(player)
end

function PlayerManagerService:ResetPlayerRocks(player)
	self.Components.PlayerStripDataInitializer:InitStripDataForPlayer(player)
	RockService:ResetPlayerHitboxes(player)
end

-- ==== Test function
function PlayerManagerService:WaitForPlayerStats(player)
	while player:IsDescendantOf(Players) do
		local stats = self.PlayerStats[player.UserId]

		if stats then
			return stats
		end

		task.wait()
	end

	return nil
end

function PlayerManagerService:DisableJump(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

function PlayerManagerService:ApplyWalkSpeed(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")

	if not humanoid then
		return
	end

	if not self.PlayerStats[player.UserId] or self.PlayerStats[player.UserId]["WalkSPeed"] then
		return
	end

	humanoid.WalkSpeed = self.PlayerStats[player.UserId]["WalkSpeed"]
end

function PlayerManagerService:KnitStart() end

function PlayerManagerService:KnitInit()
	RockService = Knit.GetService("RockService")
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)

	-- ==== Player Init ====
	local function onPlayerAdded(player: Player)
		self.Components.PlayerStripDataInitializer:InitStripDataForPlayer(player)
		self.Components.PlayerCollisionInitializer:InitCollisionForPlayer(player)
		task.spawn(function()
			self.Components.PlayerStatsInitializer:InitPlayerStats(player)
		end)

		player.CharacterAdded:Connect(function(character)
			self:WaitForPlayerStats(player)

			self:CreateWeaponHitbox(player)

			self:ApplyWalkSpeed(player)

			self:DisableJump(player)
		end)

		self:WaitForPlayerStats(player)

		self.Components.PlayerWeaponHitboxManager:StartPlayerLoop(player)
	end

	-- Игроки, уже подключённые к моменту KnitInit (гонка старта сервера/клиентов
	-- в локальном мультиплеере): их PlayerAdded уже отгремел и второй раз не
	-- сработает, поэтому без этого прохода они никогда не получают
	-- <userId>_Rock — а клиент вешается на WaitForChild этой папки навсегда
	-- (см. RockVisualizer), блокируя загрузку вообще всех контроллеров после неё.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		self.Components.DataCleaner:CleanPlayerData(player)
	end)
	-- ========
end

return PlayerManagerService
