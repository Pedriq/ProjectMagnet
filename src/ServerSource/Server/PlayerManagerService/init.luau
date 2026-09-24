local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local PlayerManagerService = Knit.CreateService({
	Name = "PlayerManagerService",
	PlayerStripData = {},
	PlayerThreads = {},
	PlayerStats = {},
	PlayersInventories = {},
	LeaderstatsConnections = {},
	-- Временные баффы к множителям: [userId] = { [buffType] = { ExpiresAt, Bonus } }.
	-- См. BuffHandler / BuffConfig.
	PlayerBuffs = {},
	Client = {
		-- Fire(player, stripId, rockIndex, maxHp, newHp) — за КАЖДЫЙ задетый камень
		-- (для визуала конкретного камня — ShakeRock/FlashRock в RockController).
		HitRock = Knit.CreateSignal(),
		-- Fire(player) — ровно 1 раз за взмах (см. PlayerMagnetHitboxManager),
		-- даже если этим взмахом задето сразу несколько стеблей.
		-- Для UI-фидбека начисления силы (ClickEffect) — не привязан к конкретному камню.
		AttackHit = Knit.CreateSignal(),
		-- Инвентарь для ПЕРЕНОСА (не склад): Fire(player, count, capacity)
		CarryInventoryChanged = Knit.CreateSignal(),
		-- Fire(player, friendsCount, bonusPercent) — сколько друзей сейчас в сессии
		-- и текущий бонус к силе за клик (см. FriendBonusHandler)
		FriendBonusChanged = Knit.CreateSignal(),
		-- Fire(player, buffType, expiresAt, bonus) — временный бафф куплен/продлён
		-- (см. BuffHandler). expiresAt — workspace:GetServerTimeNow() момент истечения.
		BuffChanged = Knit.CreateSignal(),
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
	return self.PlayerStripData[userId][stripId][rockIndex]
end

-- Вернуть игроку разбитые камни: HP всех камней сбрасывается к максимуму,
-- хитбоксы ближайших полос пересоздаются на следующем тике RockService.
function PlayerManagerService:ResetPlayerRock(player)
	self.Components.PlayerStripDataInitializer:InitStripDataForPlayer(player)
	RockService:ResetPlayerHitboxes(player)
end

function PlayerManagerService:ChangeMagnet(player, magnetData)
	ProfileService:ChangeData(player, { "Magnet" }, magnetData)
end

-- Мечи, которыми игрок владеет: map[magnetName] = true (см. MagnetData / MagnetShopHandler).
function PlayerManagerService:GetPlayerOwnedMagnets(player)
	return ProfileService:GetData(player, { "OwnedMagnets" }) or {}
end

function PlayerManagerService:SetMagnetOwned(player, magnetName)
	ProfileService:ChangeData(player, { "OwnedMagnets", magnetName }, true)
end

-- Панель мечей: купить меч за Money (сразу экипируется). Сервер сам считает цену.
function PlayerManagerService:BuyMagnet(player, magnetName)
	return self.Components.MagnetShopHandler:BuyWithMoney(player, magnetName)
end

-- Панель мечей: экипировать уже купленный меч.
function PlayerManagerService:EquipMagnet(player, magnetName)
	return self.Components.MagnetShopHandler:EquipMagnet(player, magnetName)
end

function PlayerManagerService.Client:BuyMagnet(player, magnetName)
	return self.Server:BuyMagnet(player, magnetName)
end

function PlayerManagerService.Client:EquipMagnet(player, magnetName)
	return self.Server:EquipMagnet(player, magnetName)
end

-- Донат-меч (Game Pass, MagnetData[name].GamePassId): открыть окно покупки.
-- Владение обработает MagnetGamePassPurchaseHandler (PromptGamePassPurchaseFinished),
-- Data.ownedMagnets/Data.magnet прилетят через ProfileService.UpdateSpecificData.
function PlayerManagerService:PromptMagnetRobuxPurchase(player, magnetName)
	self.Components.MagnetGamePassPurchaseHandler:PromptPurchase(player, magnetName)
end

function PlayerManagerService.Client:PromptMagnetRobuxPurchase(player, magnetName)
	return self.Server:PromptMagnetRobuxPurchase(player, magnetName)
end

-- Обычный меч «Cutters» за Robux (MagnetData[name].RobuxProductId) — в обход
-- цены Money, НЕ донат-меч. Не путать с PromptMagnetRobuxPurchase выше (та —
-- для Game Pass'ов OP Magnets). Владение обработает MagnetRobuxPurchaseHandler
-- через MarketplaceReceiptRouter (дев-продукт, не Game Pass).
function PlayerManagerService:PromptMagnetDevProductPurchase(player, magnetName)
	self.Components.MagnetRobuxPurchaseHandler:PromptPurchase(player, magnetName)
end

function PlayerManagerService.Client:PromptMagnetDevProductPurchase(player, magnetName)
	return self.Server:PromptMagnetDevProductPurchase(player, magnetName)
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

-- Заблокированные от продажи имена предметов (панель Sell Loot, кнопка Lock):
-- map[itemName] = true. Блокировка — по имени (вся стопка), не по id.
function PlayerManagerService:GetPlayerLockedItems(player)
	return ProfileService:GetData(player, { "LockedItems" }) or {}
end

function PlayerManagerService:IsItemNameLocked(player, itemName)
	return self:GetPlayerLockedItems(player)[itemName] == true
end

-- Переключить блокировку продажи для всех предметов с этим именем (текущих и
-- будущих — блокировка живёт по имени, а не по конкретным id).
function PlayerManagerService:ToggleItemLock(player, itemName)
	local locked = self:IsItemNameLocked(player, itemName)
	ProfileService:ChangeData(player, { "LockedItems", itemName }, if locked then nil else true)
	return not locked
end

function PlayerManagerService.Client:ToggleItemLock(player, itemName)
	return self.Server:ToggleItemLock(player, itemName)
end

function PlayerManagerService:GetPlayerMagnet(player)
	return ProfileService:GetData(player, { "Magnet" })
end

function PlayerManagerService:ChangePlayerMagnetism(player, magnetism)
	ProfileService:ChangeData(player, { "Stats", "Magnetism" }, magnetism)
end

-- Множитель денег за ребёрс + бонус активного временного баффа + бонус
-- постоянного донат-множителя (все складываются, см. BuffHandler:GetBonus /
-- BuffConfig, PermanentMultiplierHandler:GetBonus / PermanentMultiplierConfig).
function PlayerManagerService:GetPlayerCashMultiplier(player)
	local base = tonumber(ProfileService:GetData(player, { "Multipliers", "Cash" })) or 1
	return base
		+ self.Components.BuffHandler:GetBonus(player, "Money")
		+ self.Components.PermanentMultiplierHandler:GetBonus(player, "Money")
end

function PlayerManagerService:ChangePlayerCashMultiplier(player, multiplier)
	ProfileService:ChangeData(player, { "Multipliers", "Cash" }, multiplier)
end

-- Множитель силы за ребёрс + бонус активного временного баффа + бонус
-- постоянного донат-множителя (все складываются, см. BuffHandler:GetBonus /
-- BuffConfig, PermanentMultiplierHandler:GetBonus / PermanentMultiplierConfig).
function PlayerManagerService:GetPlayerMagnetismMultiplier(player)
	local base = tonumber(ProfileService:GetData(player, { "Multipliers", "Magnetism" })) or 1
	return base
		+ self.Components.BuffHandler:GetBonus(player, "Magnetism")
		+ self.Components.PermanentMultiplierHandler:GetBonus(player, "Magnetism")
end

function PlayerManagerService:ChangePlayerMagnetismMultiplier(player, multiplier)
	ProfileService:ChangeData(player, { "Multipliers", "Magnetism" }, multiplier)
end

-- Клиент жмёт «купить» на карточке буста (панель Shop): промпт покупки
-- дев-продукта; выдача баффа — через MarketplaceReceiptRouter (BuffPurchaseHandler).
function PlayerManagerService:PromptBuffPurchase(player, productId)
	self.Components.BuffPurchaseHandler:PromptPurchase(player, productId)
end

function PlayerManagerService.Client:PromptBuffPurchase(player, productId)
	self.Server:PromptBuffPurchase(player, productId)
end

-- Клиент жмёт «купить» на BuffBuyButton (HUD, постоянный множитель): промпт
-- покупки дев-продукта следующей ступени; выдача — через MarketplaceReceiptRouter
-- (PermanentMultiplierPurchaseHandler).
function PlayerManagerService:PromptPermanentMultiplierPurchase(player, productId)
	self.Components.PermanentMultiplierPurchaseHandler:PromptPurchase(player, productId)
end

function PlayerManagerService.Client:PromptPermanentMultiplierPurchase(player, productId)
	self.Server:PromptPermanentMultiplierPurchase(player, productId)
end

-- Клиент жмёт «купить» на PowerBuyButton (HUD, разовая покупка силы): промпт
-- покупки дев-продукта; выдача — через MarketplaceReceiptRouter (PowerPackPurchaseHandler).
function PlayerManagerService:PromptPowerPackPurchase(player, productId)
	self.Components.PowerPackPurchaseHandler:PromptPurchase(player, productId)
end

function PlayerManagerService.Client:PromptPowerPackPurchase(player, productId)
	self.Server:PromptPowerPackPurchase(player, productId)
end

-- Клиент жмёт «Sell x2» (панель Sell Loot): промпт покупки дев-продукта; сама
-- продажа всего инвентаря с x2 — в SellBoostPurchaseHandler, по факту чека.
function PlayerManagerService:PromptSellBoostPurchase(player)
	self.Components.SellBoostPurchaseHandler:PromptPurchase(player)
end

function PlayerManagerService.Client:PromptSellBoostPurchase(player)
	self.Server:PromptSellBoostPurchase(player)
end

function PlayerManagerService:GetPlayerRebirths(player)
	return ProfileService:GetData(player, { "Stats", "Rebirth" })
end

function PlayerManagerService:ChangePlayerRebirths(player, rebirths)
	ProfileService:ChangeData(player, { "Stats", "Rebirth" }, rebirths)
end

function PlayerManagerService:GetPlayerLevel(player)
	return ProfileService:GetData(player, { "Stats", "Level" })
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

-- Прокачиваемые статы: ключ в профиле Stats.<key> <-> атрибут персонажа "<key>Level",
-- который слушает PlayerStatsInitializer и пересчитывает PlayerStatsContainer.
local STAT_LEVEL_ATTRIBUTE = {
	Range = "RangeLevel",
	Agility = "AgilityLevel",
	Capacity = "CapacityLevel",
	Mobility = "MobilityLevel",
}

function PlayerManagerService:GetPlayerStatLevel(player, statKey)
	return ProfileService:GetData(player, { "Stats", statKey })
end

-- Записать новый уровень стата: и в профиль (сохранение + зеркало клиента), и в
-- атрибут (триггерит пересчёт статов у PlayerStatsInitializer).
function PlayerManagerService:ChangePlayerStatLevel(player, statKey, level)
	local attribute = STAT_LEVEL_ATTRIBUTE[statKey]
	assert(attribute, "Unknown stat key: " .. tostring(statKey))

	ProfileService:ChangeData(player, { "Stats", statKey }, level)
	player:SetAttribute(attribute, level)
end

function PlayerManagerService:BuyStatUpgrade(player, statKey)
	return self.Components.StatUpgradeHandler:BuyWithMoney(player, statKey)
end

-- Клиент жмёт «прокачать за Money»: сервер сам проверит цену и спишет деньги.
function PlayerManagerService.Client:BuyStatUpgrade(player, statKey)
	return self.Server:BuyStatUpgrade(player, statKey)
end

function PlayerManagerService:PromptStatRobuxUpgrade(player, statKey)
	self.Components.StatUpgradeHandler:PromptRobuxUpgrade(player, statKey)
end

-- Клиент жмёт «купить прокачку за донат»: сервер вызывает промпт покупки дев-продукта.
function PlayerManagerService.Client:PromptStatRobuxUpgrade(player, statKey)
	self.Server:PromptStatRobuxUpgrade(player, statKey)
end

function PlayerManagerService:GetPlayerStatsValues(player)
	return self.PlayerStats[player.UserId]
end

function PlayerManagerService:CreateMagnetHitbox(player)
	-- resolveKey — на случай старых профилей, у которых в Magnet.Name осело
	-- отображаемое имя вместо ключа (баг MagnetShopHandler:EquipMagnet, уже
	-- пофикшен для новых записей, но старые сохранёнки сами себя не чинят).
	local magnetKey = MagnetData.resolveKey(self:GetPlayerMagnet(player).Name) or "Stick"
	self.Components.PlayerMagnetHitboxManager:CreateMagnetHitbox(player, magnetKey)
end

function PlayerManagerService:GiveMagnet(player)
	self.Components.MagnetHandler:GiveMagnet(player)
end

-- Руда, которую игрок несёт (см. PlayerOreInventory). Возвращает, сколько
-- кусочков реально влезло.
function PlayerManagerService:AddOrePieces(player, oreId, pieces)
	return self.Components.PlayerOreInventory:AddPieces(player, oreId, pieces)
end

function PlayerManagerService:IsCarryFull(player)
	return self.Components.PlayerOreInventory:IsFull(player)
end

-- Сохранить несомую руду в профиль (Save-зона на базе).
function PlayerManagerService:SaveCarriedOres(player)
	self.Components.PlayerOreInventory:SaveToProfile(player)
end

-- Забрать у игрока один кусочек руды (пресс, см. PressService). Возвращает oreId, вес.
function PlayerManagerService:TakeOrePiece(player)
	return self.Components.PlayerOreInventory:TakePiece(player)
end

-- Текущий инвентарь ДЛЯ ПЕРЕНОСА: Count — суммарный вес несомой руды,
-- Capacity — вместимость (в единицах веса).
function PlayerManagerService:GetCarryInfo(player)
	local stats = self.PlayerStats[player.UserId] or self:WaitForPlayerStats(player)
	local inv = self.PlayersInventories[player.UserId]
	return {
		Count = (inv and inv.TotalWeight) or 0,
		Capacity = (stats and stats.Capacity) or BaseStatsValues.InvetoryCapacity,
	}
end

function PlayerManagerService.Client:GetCarryInfo(player)
	return self.Server:GetCarryInfo(player)
end

-- Отправить клиенту актуальные count/capacity инвентаря переноса
function PlayerManagerService:PushCarryInfo(player)
	if not player or not player.Parent then
		return
	end
	local info = self:GetCarryInfo(player)
	self.Client.CarryInventoryChanged:Fire(player, info.Count, info.Capacity)
end

function PlayerManagerService:SaveItemToPlayer(player, itemId, itemData)
	return ProfileService:AddItem(player, itemId, itemData)
end

function PlayerManagerService:RemoveItemToPlayer(player, itemId)
	return ProfileService:RemoveItem(player, itemId)
end

function PlayerManagerService:ClearTresuresToPlayer(player)
	return ProfileService:ClearItems(player)
end

function PlayerManagerService:SellItem(player, itemId)
	self.Components.PlayerTreasureManager:SellItem(player, itemId)
end

function PlayerManagerService:SellItems(player, itemIds)
	self.Components.PlayerTreasureManager:SellItems(player, itemIds)
end

function PlayerManagerService:SellAllItems(player)
	self.Components.PlayerTreasureManager:SellAllItems(player)
end

-- Продать один предмет со склада (цена = Price * множитель денег, см. PlayerTreasureManager).
function PlayerManagerService.Client:SellItem(player, itemId)
	self.Server:SellItem(player, itemId)
end

-- Продать пачку предметов (одна «стопка» одинаковых предметов в панели Sell Loot).
function PlayerManagerService.Client:SellItems(player, itemIds)
	self.Server:SellItems(player, itemIds)
end

function PlayerManagerService.Client:SellAllItems(player)
	self.Server:SellAllItems(player)
end

function PlayerManagerService:RebirthPlayer(player)
	self.Components.RebirthHandler:Rebirth(player)
end

-- Клиент просит ребёрс: сервер сам проверит уровень (RebirthHandler:CanRebirth).
function PlayerManagerService.Client:Rebirth(player)
	self.Server:RebirthPlayer(player)
end

-- Телепорт игрока на респавн его мира (кнопка Base в HUD).
function PlayerManagerService:TeleportToWorldSpawn(player)
	self.Components.WorldSpawnHandler:TeleportToWorldSpawn(player)
end

function PlayerManagerService.Client:TeleportToWorldSpawn(player)
	self.Server:TeleportToWorldSpawn(player)
end

-- Сколько Roblox-друзей игрока сейчас находятся в этой же игре (кэш, см. FriendBonusHandler).
function PlayerManagerService:GetFriendsInSessionCount(player)
	return self.Components.FriendBonusHandler:GetCount(player)
end

-- Текущий бонус к силе за клик от друзей в сессии, в процентах (5% за друга).
function PlayerManagerService:GetFriendBonusPercent(player)
	return self.Components.FriendBonusHandler:GetPercent(player)
end

-- То же самое множителем (1 = без бонуса, 1.05 = +5% и т.д.) — используется в ClickHandler.
function PlayerManagerService:GetFriendBonusMultiplier(player)
	return self.Components.FriendBonusHandler:GetMultiplier(player)
end

function PlayerManagerService:GetFriendBonusInfo(player)
	return {
		Count = self:GetFriendsInSessionCount(player),
		Percent = self:GetFriendBonusPercent(player),
	}
end

-- Клиент запрашивает актуальный бонус при старте (кнопка Invite в HUD).
function PlayerManagerService.Client:GetFriendBonusInfo(player)
	return self.Server:GetFriendBonusInfo(player)
end

-- Активные временные баффы игрока (уже без истёкших) — снапшот при старте
-- клиента, до того как он подпишется на BuffChanged (см. Data.luau).
function PlayerManagerService:GetActiveBuffs(player)
	return self.Components.BuffHandler:GetActiveBuffs(player)
end

function PlayerManagerService.Client:GetActiveBuffs(player)
	return self.Server:GetActiveBuffs(player)
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

function PlayerManagerService:KnitStart()
	-- следит за зонами с тегом "SaveItemsZone": сохраняет принесённые предметы
	-- игроков в зоне и возвращает им срубленный камень
	self.Components.SaveItemsZoneHandler:StartWatching()

	-- ==== For test
	-- local testSellpart = workspace:WaitForChild("TestSellOne") :: BasePart
	-- local testSellAllpart = workspace:WaitForChild("TestSellAll") :: BasePart

	-- testSellpart.Touched:Connect(function()
	-- 	self:SellItem(Players:FindFirstChild("pedreONTHEWAY"), testSellpart:GetAttribute("Id"))

	-- 	print(self:GetAllPlayerData(Players:FindFirstChild("pedreONTHEWAY")))
	-- end)

	-- testSellAllpart.Touched:Connect(function()
	-- 	self:SellAllItems(Players:FindFirstChild("pedreONTHEWAY"))

	-- 	print(self:GetAllPlayerData(Players:FindFirstChild("pedreONTHEWAY")))
	-- end)

	-- self:ClearTresuresToPlayer(Players:WaitForChild("pedreONTHEWAY"))
	-- =====
end

function PlayerManagerService:KnitInit()
	RockService = Knit.GetService("RockService")
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)

	-- ==== Player Init ====
	Players.PlayerAdded:Connect(function(player: Player)
		self.Components.PlayerStripDataInitializer:InitStripDataForPlayer(player)
		self.Components.PlayerCollisionInitializer:InitCollisionForPlayer(player)
		task.spawn(function()
			self.Components.PlayerStatsInitializer:InitPlayerStats(player)
		end)
		task.spawn(function()
			self.Components.LeaderstatsInitializer:InitLeaderstats(player)
		end)
		task.spawn(function()
			self.Components.BuffHandler:RestorePlayer(player)
		end)

		player.CharacterAdded:Connect(function(character)
			self:GiveMagnet(player)

			self:WaitForPlayerStats(player)

			self:CreateMagnetHitbox(player, self:GetPlayerMagnet(player).Name)

			self:ApplyWalkSpeed(player)
		end)

		self:WaitForPlayerStats(player)

		self.Components.PlayerMagnetHitboxManager:StartPlayerLoop(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Components.DataCleaner:CleanPlayerData(player)
	end)
	-- ========
end

return PlayerManagerService
