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
-- extraMultiplier — доп. множитель поверх обычного cashMultiplier (например,
-- x2 за донат-продукт "Sell x2", см. SellBoostConfig/SellBoostPurchaseHandler).
function PlayerTreasureManager:SellItem(player, itemId, extraMultiplier: number?)
	local playerItems = PlayerManagerService:GetPlayerItems(player)

	if not playerItems[itemId] then
		print("Player dont have item with id " .. itemId)
		return
	end

	if not playerItems[itemId].Price or not PlayerManagerService:GetPlayerMoney(player) then
		print("Invalid item price or player money")
		return
	end

	-- заблокированные от продажи предметы (кнопка Lock) не продаются — ни по
	-- одному, ни через Sell All/Sell x2. Проверка на сервере, а не только на
	-- клиенте (там кнопка Sell уже задизейблена), т.к. SellAllItems не идёт
	-- через клиентский UI-стейт вообще.
	if PlayerManagerService:IsItemNameLocked(player, playerItems[itemId].Name) then
		return
	end

	-- print(playerItems[itemId].Price)
	-- print(PlayerManagerService:GetPlayerMoney(player))

	-- множитель денег за ребёрсы/баффы/донат: применяется к цене продажи предмета
	local cashMultiplier = PlayerManagerService:GetPlayerCashMultiplier(player) or 1
	local payout = EtNum.mul(playerItems[itemId].Price, cashMultiplier * (extraMultiplier or 1))

	local newMoney = EtNum.add(payout, PlayerManagerService:GetPlayerMoney(player))

	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(newMoney))

	PlayerManagerService:RemoveItemToPlayer(player, itemId)
end

-- Продать перечисленные предметы (стопка одинаковых в панели Sell Loot).
-- id приходят с клиента — SellItem сам проверяет, что предмет реально есть у игрока.
function PlayerTreasureManager:SellItems(player, itemIds, extraMultiplier: number?)
	if type(itemIds) ~= "table" then
		return
	end

	for _, id in ipairs(itemIds) do
		if type(id) == "string" then
			self:SellItem(player, id, extraMultiplier)
		end
	end
end

function PlayerTreasureManager:SellAllItems(player, extraMultiplier: number?)
	local playerItems = PlayerManagerService:GetPlayerItems(player)

	-- сначала снимаем список id: SellItem удаляет ключи из этой же таблицы,
	-- а менять таблицу во время pairs() по ней нельзя (часть предметов пропустится).
	local ids = {}
	for id in pairs(playerItems) do
		table.insert(ids, id)
	end

	for _, id in ipairs(ids) do
		self:SellItem(player, id, extraMultiplier)
	end
end

function PlayerTreasureManager.Start() end

function PlayerTreasureManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PlayerTreasureManager
