local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local FriendBonusHandler = {}

---- Knit Services
local PlayerManagerService

---- Datas
-- Бонус к силе за клик за каждого друга (из Roblox-друзей игрока), который сейчас
-- находится в этой же игре: 1 друг = +5%, 2 друга = +10% и т.д.
local PERCENT_PER_FRIEND = 5

-- [userId] = сколько друзей сейчас в сессии (кэш, чтобы не дёргать IsFriendsWith на каждый клик)
local friendsInSession = {}

local function computeFriendsInSession(player: Player): number
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				count += 1
			end
		end
	end
	return count
end

local function recalculate(player: Player)
	if not player or not player.Parent then
		return
	end

	local count = computeFriendsInSession(player)
	local prevCount = friendsInSession[player.UserId]
	friendsInSession[player.UserId] = count

	if prevCount ~= count then
		PlayerManagerService.Client.FriendBonusChanged:Fire(player, count, count * PERCENT_PER_FRIEND)
	end
end

local function recalculateAll()
	for _, player in Players:GetPlayers() do
		recalculate(player)
	end
end

function FriendBonusHandler:GetCount(player: Player): number
	return friendsInSession[player.UserId] or 0
end

function FriendBonusHandler:GetPercent(player: Player): number
	return self:GetCount(player) * PERCENT_PER_FRIEND
end

function FriendBonusHandler:GetMultiplier(player: Player): number
	return 1 + self:GetPercent(player) / 100
end

function FriendBonusHandler.Start()
	-- новый игрок мог оказаться другом уже подключённых — пересчитываем всех
	Players.PlayerAdded:Connect(function()
		task.defer(recalculateAll)
	end)

	Players.PlayerRemoving:Connect(function(player)
		friendsInSession[player.UserId] = nil
		task.defer(recalculateAll)
	end)

	recalculateAll()
end

function FriendBonusHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return FriendBonusHandler
