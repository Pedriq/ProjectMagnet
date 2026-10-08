local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerTreasureManager = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
-- Продать пачку предметов за ОДНУ запись денег (раньше — отдельная запись и сигнал клиенту на каждый предмет:
-- Sell All на большом складе заливал сеть тысячами пакетов). id приходят с клиента — каждый проверяется:
-- предмет должен реально лежать у игрока и не быть заблокированным (кнопка Lock; проверка тут, а не только в UI,
-- потому что SellAll / Sell x2 вообще не идут через клиентский стейт). Цена берётся из профиля, не от клиента.
function PlayerTreasureManager:_SellBatch(player, itemIds: { string }, extraMultiplier: number?)
	local playerItems = PlayerManagerService:GetPlayerItems(player)
	local money = PlayerManagerService:GetPlayerMoney(player)
	if not playerItems or not money then
		return
	end

	local cashMultiplier = PlayerManagerService:GetPlayerCashMultiplier(player) or 1
	local multiplier = cashMultiplier * (extraMultiplier or 1)

	local total = EtNum.convert("0")
	local sold = {}
	for _, itemId in ipairs(itemIds) do
		local item = playerItems[itemId]
		if
			type(item) == "table"
			and item.Price
			and not sold[itemId]
			and not PlayerManagerService:IsItemNameLocked(player, item.Name)
		then
			sold[itemId] = true
			total = EtNum.add(total, EtNum.mul(item.Price, multiplier))
		end
	end

	if next(sold) == nil then
		return
	end

	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.add(total, money)))
	-- Продали всё, что есть (типичный Sell All) — одна запись Clear вместо отдельного сигнала репликации на
	-- каждый предмет: при сотнях предметов это сотни сетевых пакетов и перерисовок панели подряд.
	local soldCount, totalCount = 0, 0
	for _ in pairs(sold) do
		soldCount += 1
	end
	for _ in pairs(playerItems) do
		totalCount += 1
	end
	if soldCount == totalCount then
		PlayerManagerService:ClearTresuresToPlayer(player)
	else
		for itemId in pairs(sold) do
			PlayerManagerService:RemoveItemToPlayer(player, itemId)
		end
	end
end

-- extraMultiplier — доп. множитель поверх обычного cashMultiplier (например,
-- x2 за донат-продукт "Sell x2", см. SellBoostConfig/SellBoostPurchaseHandler).
function PlayerTreasureManager:SellItem(player, itemId, extraMultiplier: number?)
	if type(itemId) ~= "string" then
		return
	end
	self:_SellBatch(player, { itemId }, extraMultiplier)
end

-- Продать перечисленные предметы (стопка одинаковых в панели Sell Loot).
-- id приходят с клиента — SellItem сам проверяет, что предмет реально есть у игрока.
function PlayerTreasureManager:SellItems(player, itemIds, extraMultiplier: number?)
	if type(itemIds) ~= "table" then
		return
	end

	local ids = {}
	for _, id in ipairs(itemIds) do
		if type(id) == "string" then
			table.insert(ids, id)
		end
	end
	self:_SellBatch(player, ids, extraMultiplier)
end

function PlayerTreasureManager:SellAllItems(player, extraMultiplier: number?)
	local playerItems = PlayerManagerService:GetPlayerItems(player)

	-- сначала снимаем список id: продажа удаляет ключи из этой же таблицы,
	-- а менять таблицу во время pairs() по ней нельзя (часть предметов пропустится).
	local ids = {}
	for id in pairs(playerItems) do
		table.insert(ids, id)
	end

	self:_SellBatch(player, ids, extraMultiplier)
end

function PlayerTreasureManager.Start() end

function PlayerTreasureManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PlayerTreasureManager
