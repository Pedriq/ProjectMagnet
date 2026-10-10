local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)
local RateLimiter = require(ReplicatedStorage.SharedSource.Utilities.RateLimiter)

-- Всё, что приходит в Client:* методы, — недоверенный ввод: тип и длина проверяются здесь, лимит частоты — через RateLimiter.
local MAX_NAME_LENGTH = 64
local MAX_SELL_BATCH = 500 -- id предметов в одном вызове SellItems

local function isShortString(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_NAME_LENGTH
end

local function isProductId(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value % 1 == 0
end

-- Имена всех предметов, которые вообще существуют (пресс делает их из TreasuresConfig): блокировать от продажи
-- можно только их, иначе клиент засорит профиль произвольными ключами LockedItems.
local VALID_ITEM_NAMES: { [string]: boolean } = {}
for _, items in pairs(TreasuresConfig) do
	if type(items) == "table" then
		for _, item in ipairs(items) do
			if type(item) == "table" and type(item.Name) == "string" then
				VALID_ITEM_NAMES[item.Name] = true
			end
		end
	end
end
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
		-- Fire(player, hits) — ОДИН раз за взмах/свип сразу по всем задетым камням:
		-- hits = { {stripId, rockIndex, maxHp, newHp}, ... } (для визуала конкретного
		-- камня — ShakeRock/FlashRock в RockController). Батч вместо remote'а на камень —
		-- при беге через поле камней много, и сетевой трафик/нагрузка на мобильных росла.
		HitRocks = Knit.CreateSignal(),
		-- Fire(player) — ровно 1 раз за взмах (см. PlayerMagnetHitboxManager),
		-- даже если этим взмахом задето сразу несколько стеблей.
		-- Для UI-фидбека начисления силы (ClickEffect) — не привязан к конкретному камню.
		AttackHit = Knit.CreateSignal(),
		-- Fire(player, neededWeight, freeWeight) — магнит дотянулся до камня, но кусочек руды не
		-- влезает в свободное место (полоска может быть и не на 100%): клиент показывает BAG FULL.
		CarryBlocked = Knit.CreateSignal(),
		-- Инвентарь для ПЕРЕНОСА (не склад): Fire(player, count, capacity)
		CarryInventoryChanged = Knit.CreateSignal(),
		-- Fire(player, friendsCount, bonusPercent) — сколько друзей сейчас в сессии
		-- и текущий бонус к силе за клик (см. FriendBonusHandler)
		FriendBonusChanged = Knit.CreateSignal(),
		-- Fire(player, buffType, expiresAt, bonus) — временный бафф куплен/продлён
		-- (см. BuffHandler). expiresAt — workspace:GetServerTimeNow() момент истечения.
		BuffChanged = Knit.CreateSignal(),
		-- Fire(player, checkpointPart, savedWeight) — игрок прошёл чекпоинт, руда сохранена
		-- (см. CheckpointHandler). Клиент делает этот парт прозрачным.
		CheckpointPassed = Knit.CreateSignal(),
		-- Fire(player) — ресет чекпоинтов после Entrance -> Save: вернуть видимость.
		CheckpointsReset = Knit.CreateSignal(),
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
	-- данные игрока могли быть уже очищены (вышел) или полосы нет — тогда просто nil, а не ошибка
	local strips = self.PlayerStripData[userId]
	local strip = strips and strips[stripId]
	return strip and strip[rockIndex]
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

-- Разовая миграция ключей после ребрендинга «мечи -> магниты» (см.
-- MagnetData.LegacyKeyAliases): у уже сохранённых профилей OwnedMagnets/Magnet.Name
-- всё ещё хранят СТАРЫЕ ключи (Reconcile() их не переименовывает, только
-- дозаполняет отсутствующее) — без этого игрок не видит купленные магниты в
-- магазине (Owns сверяет по новому ключу) и в руке (GiveMagnet не находит
-- ассет). Идемпотентно: на уже смигрированном профиле ничего не меняет.
function PlayerManagerService:_MigrateLegacyMagnetKeys(player)
	local owned = ProfileService:GetData(player, { "OwnedMagnets" }) or {}

	local renames = {}
	for storedKey in pairs(owned) do
		local resolved = MagnetData.resolveKey(storedKey)
		if resolved and resolved ~= storedKey then
			table.insert(renames, { From = storedKey, To = resolved })
		end
	end
	for _, rename in ipairs(renames) do
		ProfileService:ChangeData(player, { "OwnedMagnets", rename.To }, true)
		ProfileService:ChangeData(player, { "OwnedMagnets", rename.From }, nil)
	end

	local magnet = ProfileService:GetData(player, { "Magnet" })
	local currentName = magnet and magnet.Name
	if currentName then
		local resolved = MagnetData.resolveKey(currentName)
		if resolved and resolved ~= currentName then
			ProfileService:ChangeData(player, { "Magnet", "Name" }, resolved)
		end
	end
end

-- Панель мечей: купить меч за Money (сразу экипируется). Сервер сам считает цену.
function PlayerManagerService:BuyMagnet(player, magnetName)
	return self.Components.MagnetShopHandler:BuyWithMoney(player, magnetName)
end

-- Панель мечей: экипировать уже купленный меч.
function PlayerManagerService:EquipMagnet(player, magnetName)
	return self.Components.MagnetShopHandler:EquipMagnet(player, magnetName)
end

-- Обучение пройдено: сохраняем в профиле навсегда (клиент сам решает, когда оно закончено).
function PlayerManagerService:CompleteTutorial(player)
	-- воронка обучения: шаг "Completed" пишет сервер (только если воронка в этой сессии была открыта)
	pcall(function()
		Knit.GetService("AnalyticsFunnelService"):TutorialCompleted(player)
	end)
	ProfileService:ChangeData(player, { "Tutorial", "Completed" }, true)
end

function PlayerManagerService.Client:CompleteTutorial(player)
	if not RateLimiter.Allow(player, "CompleteTutorial", 2) then
		return
	end
	self.Server:CompleteTutorial(player)
end

-- Громкость из окна Settings: kind = "Music" | "Sfx", value 0..1 (округляем до 1%, чтобы не писать шум в профиль).
local AUDIO_SETTING_KEYS = { Music = "MusicVolume", Sfx = "SfxVolume" }

function PlayerManagerService:SetAudioSetting(player, kind: string, value: number)
	local key = AUDIO_SETTING_KEYS[kind]
	if key then
		ProfileService:ChangeData(player, { "Settings", key }, math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100)
	end
end

function PlayerManagerService.Client:SetAudioSetting(player, kind, value)
	if
		not AUDIO_SETTING_KEYS[kind]
		or type(value) ~= "number"
		or value ~= value
		or not RateLimiter.Allow(player, "SetAudioSetting", 0.2)
	then
		return
	end
	self.Server:SetAudioSetting(player, kind, value)
end

function PlayerManagerService.Client:BuyMagnet(player, magnetName)
	if not MagnetData.isMagnet(magnetName) or not RateLimiter.Allow(player, "BuyMagnet", 0.2) then
		return false
	end
	return self.Server:BuyMagnet(player, magnetName)
end

function PlayerManagerService.Client:EquipMagnet(player, magnetName)
	-- экипировка пересоздаёт модель и хитбокс — не чаще раза в полсекунды
	if not MagnetData.isMagnet(magnetName) or not RateLimiter.Allow(player, "EquipMagnet", 0.5) then
		return false
	end
	return self.Server:EquipMagnet(player, magnetName)
end

-- Донат-меч (Game Pass, MagnetData[name].GamePassId): открыть окно покупки.
-- Владение обработает MagnetGamePassPurchaseHandler (PromptGamePassPurchaseFinished),
-- Data.ownedMagnets/Data.magnet прилетят через ProfileService.UpdateSpecificData.
function PlayerManagerService:PromptMagnetRobuxPurchase(player, magnetName)
	self.Components.MagnetGamePassPurchaseHandler:PromptPurchase(player, magnetName)
end

function PlayerManagerService.Client:PromptMagnetRobuxPurchase(player, magnetName)
	if not MagnetData.isMagnet(magnetName) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
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
	if not MagnetData.isMagnet(magnetName) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
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
	if type(itemName) ~= "string" then
		return false
	end
	local locked = self:IsItemNameLocked(player, itemName)
	-- Блокировать можно только настоящие предметы (из конфига или лежащие у игрока сейчас); снять блокировку —
	-- с любого уже записанного имени.
	if not locked and not VALID_ITEM_NAMES[itemName] then
		local owned = false
		for _, item in pairs(self:GetPlayerItems(player) or {}) do
			if type(item) == "table" and item.Name == itemName then
				owned = true
				break
			end
		end
		if not owned then
			return false
		end
	end
	ProfileService:ChangeData(player, { "LockedItems", itemName }, if locked then nil else true)
	return not locked
end

function PlayerManagerService.Client:ToggleItemLock(player, itemName)
	if not isShortString(itemName) or not RateLimiter.Allow(player, "ToggleItemLock", 0.15) then
		return self.Server:IsItemNameLocked(player, tostring(itemName))
	end
	return self.Server:ToggleItemLock(player, itemName)
end

function PlayerManagerService:GetPlayerMagnet(player)
	return ProfileService:GetData(player, { "Magnet" })
end

function PlayerManagerService:ChangePlayerMagnetism(player, magnetism)
	ProfileService:ChangeData(player, { "Stats", "Magnetism" }, magnetism)
end

-- Итоговый множитель денег = ТОЧНЫЕ значения множителей, сложенные вместе:
-- ребёрс (x2 за 2 ребёрса) + активный временный бафф (x2) + постоянный донат (x2) = x6.
-- Нет баффа/покупки — слагаемое 0. Дальше база умножается на эту сумму один раз
-- (см. BuffHandler:GetMultiplier, PermanentMultiplierHandler:GetMultiplier).
function PlayerManagerService:GetPlayerCashMultiplier(player)
	local base = tonumber(ProfileService:GetData(player, { "Multipliers", "Cash" })) or 1
	return base
		+ self.Components.BuffHandler:GetMultiplier(player, "Money")
		+ self.Components.PermanentMultiplierHandler:GetMultiplier(player, "Money")
end

function PlayerManagerService:ChangePlayerCashMultiplier(player, multiplier)
	ProfileService:ChangeData(player, { "Multipliers", "Cash" }, multiplier)
end

-- Итоговый множитель силы — по тому же правилу, что и деньги (см. выше):
-- ребёрс + временный бафф + постоянный донат, точные значения складываются.
function PlayerManagerService:GetPlayerMagnetismMultiplier(player)
	local base = tonumber(ProfileService:GetData(player, { "Multipliers", "Magnetism" })) or 1
	return base
		+ self.Components.BuffHandler:GetMultiplier(player, "Magnetism")
		+ self.Components.PermanentMultiplierHandler:GetMultiplier(player, "Magnetism")
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
	if not isProductId(productId) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptBuffPurchase(player, productId)
end

-- Клиент жмёт «купить» на BuffBuyButton (HUD, постоянный множитель): промпт
-- покупки дев-продукта следующей ступени; выдача — через MarketplaceReceiptRouter
-- (PermanentMultiplierPurchaseHandler).
function PlayerManagerService:PromptPermanentMultiplierPurchase(player, productId)
	self.Components.PermanentMultiplierPurchaseHandler:PromptPurchase(player, productId)
end

function PlayerManagerService.Client:PromptPermanentMultiplierPurchase(player, productId)
	if not isProductId(productId) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptPermanentMultiplierPurchase(player, productId)
end

-- Клиент жмёт «купить» на PowerBuyButton (HUD, разовая покупка силы): промпт
-- покупки дев-продукта; выдача — через MarketplaceReceiptRouter (PowerPackPurchaseHandler).
function PlayerManagerService:PromptPowerPackPurchase(player, productId)
	self.Components.PowerPackPurchaseHandler:PromptPurchase(player, productId)
end

function PlayerManagerService.Client:PromptPowerPackPurchase(player, productId)
	if not isProductId(productId) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptPowerPackPurchase(player, productId)
end

-- Клиент жмёт «Sell x2» (панель Sell Loot): промпт покупки дев-продукта; сама
-- продажа всего инвентаря с x2 — в SellBoostPurchaseHandler, по факту чека.
function PlayerManagerService:PromptSellBoostPurchase(player)
	self.Components.SellBoostPurchaseHandler:PromptPurchase(player)
end

function PlayerManagerService.Client:PromptSellBoostPurchase(player)
	if not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptSellBoostPurchase(player)
end

-- Самый дальний открытый мир игрока (1 по умолчанию). Масштабирует Magnetism-паки
-- (PowerPackConfig.GrantFor).
function PlayerManagerService:GetPlayerWorld(player)
	return tonumber(ProfileService:GetData(player, { "Stats", "World" })) or 1
end

-- Открыть мир `world`: уровень мира только растёт (повторный/меньший — игнорируется).
-- Вызывать из кода, который пускает игрока в новый мир.
function PlayerManagerService:UnlockWorld(player, world)
	if world > self:GetPlayerWorld(player) then
		ProfileService:ChangeData(player, { "Stats", "World" }, world)
	end
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
	if not isShortString(statKey) or not RateLimiter.Allow(player, "BuyStatUpgrade", 0.08) then
		return false
	end
	return self.Server:BuyStatUpgrade(player, statKey)
end

function PlayerManagerService:PromptStatRobuxUpgrade(player, statKey)
	self.Components.StatUpgradeHandler:PromptRobuxUpgrade(player, statKey)
end

-- Клиент жмёт «купить прокачку за донат»: сервер вызывает промпт покупки дев-продукта.
function PlayerManagerService.Client:PromptStatRobuxUpgrade(player, statKey)
	if not isShortString(statKey) or not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptStatRobuxUpgrade(player, statKey)
end

-- Клиент жмёт «OP Auto Collect»: сервер сам вызывает промпт Game Pass'а.
function PlayerManagerService:PromptAutoCollectPass(player)
	self.Components.AutoCollectPassHandler:PromptPurchase(player)
end

function PlayerManagerService.Client:PromptAutoCollectPass(player)
	if not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptAutoCollectPass(player)
end

function PlayerManagerService:HasAutoCollect(player): boolean
	return self.Components.AutoCollectPassHandler:Owns(player)
end

function PlayerManagerService:GetPlayerStatsValues(player)
	return self.PlayerStats[player.UserId]
end

function PlayerManagerService:CreateMagnetHitbox(player)
	-- resolveKey — на случай старых профилей, у которых в Magnet.Name осело
	-- отображаемое имя вместо ключа (баг MagnetShopHandler:EquipMagnet, уже
	-- пофикшен для новых записей, но старые сохранёнки сами себя не чинят).
	local magnetKey = MagnetData.resolveKey(self:GetPlayerMagnet(player).Name) or "FridgeMagnet"
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

-- Влезет ли кусочек руды oreId (у руд разный вес кусочка, см. OreConfig.PieceWeight).
function PlayerManagerService:CanCarryOrePiece(player, oreId)
	return self.Components.PlayerOreInventory:CanFitPiece(player, oreId)
end

function PlayerManagerService:IsCarryFull(player)
	return self.Components.PlayerOreInventory:IsFull(player)
end

-- Сохранить несомую руду в профиль (Save-зона на базе).
function PlayerManagerService:SaveCarriedOres(player)
	self.Components.PlayerOreInventory:SaveToProfile(player)
end

-- Снова активировать все чекпоинты игрока (после круга Entrance -> Save).
function PlayerManagerService:ResetCheckpoints(player)
	self.Components.CheckpointHandler:Reset(player)
end

-- Забрать у игрока всю руду разом (пресс, см. PressService). Возвращает
-- map[oreId] = вес или nil, если руды нет.
function PlayerManagerService:TakeAllOres(player)
	return self.Components.PlayerOreInventory:TakeAll(player)
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
	-- без лимита спам вызовов плодил бы потоки, ждущие PlayerStats (WaitForPlayerStats)
	if not RateLimiter.Allow(player, "GetCarryInfo", 0.5) then
		return { Count = 0, Capacity = BaseStatsValues.InvetoryCapacity }
	end
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
	if not isShortString(itemId) or not RateLimiter.Allow(player, "Sell", 0.1) then
		return
	end
	self.Server:SellItem(player, itemId)
end

-- Продать пачку предметов (одна «стопка» одинаковых предметов в панели Sell Loot).
function PlayerManagerService.Client:SellItems(player, itemIds)
	if type(itemIds) ~= "table" or #itemIds > MAX_SELL_BATCH or not RateLimiter.Allow(player, "Sell", 0.1) then
		return
	end
	self.Server:SellItems(player, itemIds)
end

function PlayerManagerService.Client:SellAllItems(player)
	if not RateLimiter.Allow(player, "Sell", 0.3) then
		return
	end
	self.Server:SellAllItems(player)
end

function PlayerManagerService:RebirthPlayer(player)
	self.Components.RebirthHandler:Rebirth(player)
end

-- Клиент просит ребёрс: сервер сам проверит уровень (RebirthHandler:CanRebirth).
function PlayerManagerService.Client:Rebirth(player)
	if not RateLimiter.Allow(player, "Rebirth", 0.5) then
		return
	end
	self.Server:RebirthPlayer(player)
end

function PlayerManagerService:PromptSkipRebirth(player)
	self.Components.RebirthHandler:PromptSkip(player)
end

-- Клиент жмёт Skip: сервер сам выберет ступень по числу реберсов и покажет покупку.
function PlayerManagerService.Client:PromptSkipRebirth(player)
	if not RateLimiter.Allow(player, "PromptPurchase", 1.5) then
		return
	end
	self.Server:PromptSkipRebirth(player)
end

-- Телепорт игрока на респавн его мира (кнопка Base в HUD).
function PlayerManagerService:TeleportToWorldSpawn(player)
	self.Components.WorldSpawnHandler:TeleportToWorldSpawn(player)
end

function PlayerManagerService.Client:TeleportToWorldSpawn(player)
	if not RateLimiter.Allow(player, "TeleportToWorldSpawn", 0.5) then
		return
	end
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
	if not RateLimiter.Allow(player, "GetFriendBonusInfo", 1) then
		return { Count = 0, Percent = 0 }
	end
	return self.Server:GetFriendBonusInfo(player)
end

-- Активные временные баффы игрока (уже без истёкших) — снапшот при старте
-- клиента, до того как он подпишется на BuffChanged (см. Data.luau).
function PlayerManagerService:GetActiveBuffs(player)
	return self.Components.BuffHandler:GetActiveBuffs(player)
end

function PlayerManagerService.Client:GetActiveBuffs(player)
	if not RateLimiter.Allow(player, "GetActiveBuffs", 1) then
		return {}
	end
	return self.Server:GetActiveBuffs(player)
end

-- ==== Test function
function PlayerManagerService:WaitForPlayerStats(player)
	while player:IsDescendantOf(Players) do
		local stats = self.PlayerStats[player.UserId]

		if stats then
			return stats
		end

		task.wait(0.1) -- не каждый кадр: статы появляются после загрузки профиля (секунды)
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

-- Прыжка в игре нет: обнуляем силу/высоту прыжка (реплицируется клиенту, кнопка прыжка
-- на мобильных и пробел ничего не делают) и выключаем состояние Jumping.
function PlayerManagerService:DisableJump(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

function PlayerManagerService:KnitStart()
	-- следит за зонами с тегом "SaveItemsZone": сохраняет принесённые предметы
	-- игроков в зоне и возвращает им срубленный камень
	self.Components.SaveItemsZoneHandler:StartWatching()
	-- парты Workspace.Checkpoints: разовое сохранение руды до ресета на Save
	self.Components.CheckpointHandler:StartWatching()

end

function PlayerManagerService:KnitInit()
	RockService = Knit.GetService("RockService")
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)

	-- ==== Player Init ====
	local function onPlayerAdded(player: Player)
		player:SetAttribute("PM_Added", true) -- защита от двойной инициализации (см. Knit.OnStart ниже)
		-- без прыжка: и для уже заспавненного персонажа, и для всех следующих
		if player.Character then
			task.spawn(self.DisableJump, self, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(self.DisableJump, self, character)
		end)

		-- В фоне, НЕ блокируя остальной PlayerAdded: чинит старые ключи магнитов
		-- в профиле (см. _MigrateLegacyMagnetKeys). ChangeData/GetData внутри неё
		-- могут ненадолго заблокироваться (ProfileService:WaitUntilProfileLoaded,
		-- если профиль ещё грузится) — синхронный вызов здесь сдвинул бы
		-- player.CharacterAdded:Connect ниже по времени и рисковал пропустить уже
		-- случившийся спавн персонажа (а с ним — GiveMagnet/CreateMagnetHitbox и
		-- инициализацию камней). Миграции НЕ обязательно успеть до GiveMagnet —
		-- resolveKey и так понимает старые ключи через MagnetData.LegacyKeyAliases,
		-- миграция только один раз приводит сами данные профиля в порядок.
		task.spawn(function()
			self:_MigrateLegacyMagnetKeys(player)
		end)

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
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	-- игроки, зашедшие до подключения (быстрый джойн / Studio): иначе у них не будет ни статов, ни хитбокса
	-- (после старта Knit — все компоненты и сервисы уже инициализированы)
	Knit.OnStart():andThen(function()
		for _, existing in ipairs(Players:GetPlayers()) do
			-- PlayerAdded мог успеть сработать для него между KnitInit и стартом — тогда он уже помечен
			if not existing:GetAttribute("PM_Added") then
				task.spawn(onPlayerAdded, existing)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.Components.DataCleaner:CleanPlayerData(player)
	end)
	-- ========
end

return PlayerManagerService
