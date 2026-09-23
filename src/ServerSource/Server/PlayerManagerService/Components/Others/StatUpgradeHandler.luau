local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	StatUpgradeHandler — прокачка статов (Range / Agility / Capacity / Mobility)
	за Money и за донат. Конфиг цен/бонусов — StatUpgradesConfig.

	За Money: сервер считает цену из StatUpgradesConfig.CostFor(statKey, level),
	сверяет с деньгами игрока (EtNum), списывает и поднимает уровень.

	За донат: PromptProductPurchase(RobuxProductId); выдача уровней — через
	MarketplaceReceiptRouter (общий диспетчер ProcessReceipt на весь проект,
	см. SharedSource.Utilities.MarketplaceReceiptRouter).
]]

local StatUpgradeHandler = {}

---- Knit Services
local PlayerManagerService

local function currentLevel(player, statKey: string): number
	return tonumber(PlayerManagerService:GetPlayerStatLevel(player, statKey)) or 1
end

-- Поднять уровень стата на `amount` (с учётом MaxLevel). Возвращает сколько реально добавлено.
function StatUpgradeHandler:GrantLevels(player, statKey: string, amount: number): number
	local cfg = StatUpgradesConfig.Stats[statKey]
	if not cfg then
		warn(`[StatUpgrade] неизвестный стат "{statKey}"`)
		return 0
	end

	local level = currentLevel(player, statKey)
	local newLevel = math.clamp(level + amount, level, cfg.MaxLevel)
	if newLevel == level then
		return 0
	end

	PlayerManagerService:ChangePlayerStatLevel(player, statKey, newLevel)
	return newLevel - level
end

-- Покупка одного уровня за Money. true — успех, false — нет денег / макс. уровень / нет стата.
function StatUpgradeHandler:BuyWithMoney(player, statKey: string): boolean
	local cfg = StatUpgradesConfig.Stats[statKey]
	if not cfg then
		warn(`[StatUpgrade] неизвестный стат "{statKey}"`)
		return false
	end

	local level = currentLevel(player, statKey)
	if level >= cfg.MaxLevel then
		return false
	end

	local cost = StatUpgradesConfig.CostFor(statKey, level)
	local money = PlayerManagerService:GetPlayerMoney(player) or "0"

	if EtNum.me(cost, money) then -- цена > денег
		return false
	end

	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.sub(money, cost)))
	PlayerManagerService:ChangePlayerStatLevel(player, statKey, level + 1)
	return true
end

function StatUpgradeHandler:PromptRobuxUpgrade(player, statKey: string)
	local cfg = StatUpgradesConfig.Stats[statKey]
	if not cfg then
		warn(`[StatUpgrade] неизвестный стат "{statKey}"`)
		return
	end

	if not cfg.RobuxProductId or cfg.RobuxProductId == 0 then
		warn(`[StatUpgrade] RobuxProductId для "{statKey}" не задан в StatUpgradesConfig`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, cfg.RobuxProductId)
end

function StatUpgradeHandler.Start()
	-- TODO: идемпотентность чеков (кэш обработанных receipt'ов в профиле),
	-- чтобы повторная обработка чека после падения сервера не выдала уровни дважды.
	for statKey, cfg in pairs(StatUpgradesConfig.Stats) do
		if cfg.RobuxProductId and cfg.RobuxProductId ~= 0 then
			local levels = cfg.RobuxLevels or 1

			MarketplaceReceiptRouter.Register(cfg.RobuxProductId, function(player)
				StatUpgradeHandler:GrantLevels(player, statKey, levels)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end)
		end
	end
end

function StatUpgradeHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return StatUpgradeHandler
