local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)

--[[
	PlayerOreInventory — руда, которую игрок НЕСЁТ с собой (ещё не сохранена).

	PlayerManagerService.PlayersInventories[userId] = {
		Ores = { [oreId] = вес },
		TotalWeight = number,
	}

	Кусочки камней падают сюда при ударе (PlayerMagnetHitboxManager) — до
	вместимости Stats.Capacity (PlayerStatsContainer.Capacity, в единицах веса).
	На базе (SaveItemsZoneHandler) всё переносится в профиль: profile.Ores[oreId] += вес.
]]
local PlayerOreInventory = {}

---- Knit Services
local PlayerManagerService
local ProfileService

local function getInventory(player: Player)
	local inventories = PlayerManagerService.PlayersInventories
	local inv = inventories[player.UserId]
	if not inv then
		inv = { Ores = {}, TotalWeight = 0 }
		inventories[player.UserId] = inv
	end
	return inv
end

function PlayerOreInventory:GetCapacity(player: Player): number
	local stats = PlayerManagerService:GetPlayerStatsValues(player)
	return stats and stats.Capacity or 0
end

function PlayerOreInventory:GetTotalWeight(player: Player): number
	return getInventory(player).TotalWeight
end

function PlayerOreInventory:IsFull(player: Player): boolean
	return self:GetTotalWeight(player) >= self:GetCapacity(player)
end

-- Добавить `pieces` кусочков руды `oreId`. Кладётся только то, что влезает
-- целыми кусочками; возвращает, сколько кусочков реально добавлено.
function PlayerOreInventory:AddPieces(player: Player, oreId: string, pieces: number): number
	local ore = OreConfig.Get(oreId)
	if not ore or pieces <= 0 then
		return 0
	end

	local inv = getInventory(player)
	local free = self:GetCapacity(player) - inv.TotalWeight
	local fit = math.min(pieces, math.floor(free / ore.PieceWeight))
	if fit <= 0 then
		return 0
	end

	local weight = fit * ore.PieceWeight
	inv.Ores[oreId] = (inv.Ores[oreId] or 0) + weight
	inv.TotalWeight += weight

	PlayerManagerService:PushCarryInfo(player)
	return fit
end

-- Перенести всю несомую руду в профиль (profile.Ores[oreId] += вес) и очистить инвентарь.
function PlayerOreInventory:SaveToProfile(player: Player)
	local inv = getInventory(player)
	if inv.TotalWeight <= 0 then
		return
	end

	for oreId, weight in pairs(inv.Ores) do
		local saved = tonumber(ProfileService:GetData(player, { "Ores", oreId })) or 0
		ProfileService:ChangeData(player, { "Ores", oreId }, saved + weight)
	end

	inv.Ores = {}
	inv.TotalWeight = 0

	PlayerManagerService:PushCarryInfo(player)
end

-- Забрать у игрока один кусочек руды (для пресса): сначала из несомой руды,
-- потом из сохранённой (profile.Ores). Руды перебираются в порядке OreConfig.Order.
-- Возвращает oreId, вес — или nil, если руды нет совсем.
function PlayerOreInventory:TakePiece(player: Player): (string?, number)
	local inv = getInventory(player)
	for _, oreId in ipairs(OreConfig.Order) do
		local weight = inv.Ores[oreId]
		if weight and weight > 0 then
			local taken = math.min(weight, OreConfig.Get(oreId).PieceWeight)
			inv.Ores[oreId] = if weight - taken > 0 then weight - taken else nil
			inv.TotalWeight = math.max(inv.TotalWeight - taken, 0)
			PlayerManagerService:PushCarryInfo(player)
			return oreId, taken
		end
	end

	for _, oreId in ipairs(OreConfig.Order) do
		local weight = tonumber(ProfileService:GetData(player, { "Ores", oreId })) or 0
		if weight > 0 then
			local taken = math.min(weight, OreConfig.Get(oreId).PieceWeight)
			ProfileService:ChangeData(player, { "Ores", oreId }, if weight - taken > 0 then weight - taken else nil)
			return oreId, taken
		end
	end

	return nil, 0
end

function PlayerOreInventory.Start() end

function PlayerOreInventory.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ProfileService = Knit.GetService("ProfileService")
end

return PlayerOreInventory
