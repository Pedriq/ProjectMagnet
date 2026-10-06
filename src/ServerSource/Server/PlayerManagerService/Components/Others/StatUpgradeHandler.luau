local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	StatUpgradeHandler — прокачка статов (Range / Capacity / Mobility; за донат — ещё PressSpeed)
	за Money и за донат. Конфиг цен/бонусов — StatUpgradesConfig.

	За Money: сервер считает цену из StatUpgradesConfig.CostFor(statKey, level),
	сверяет с деньгами игрока (EtNum), списывает и поднимает уровень.

	За донат: платных ступеней несколько (StatUpgradesConfig.RobuxStepFor): продукт и
	цена зависят от ТЕКУЩЕГО уровня стата; PromptProductPurchase(ProductId ступени);
	выдача уровней (step.Levels) — через
	MarketplaceReceiptRouter (общий диспетчер ProcessReceipt на весь проект,
	см. SharedSource.Utilities.MarketplaceReceiptRouter).
]]

local StatUpgradeHandler = {}

---- Knit Services
local PlayerManagerService

-- Press Speed живёт не в Stats, а в profile.Press.CraftSpeed (PressService)
local PRESS_SPEED = "PressSpeed"

local function currentLevel(player, statKey: string): number
	if statKey == PRESS_SPEED then
		return Knit.GetService("PressService"):GetPressLevel(player, "CraftSpeed")
	end
	return tonumber(PlayerManagerService:GetPlayerStatLevel(player, statKey)) or 1
end

-- Поднять уровень стата на `amount` (с учётом MaxLevel). Возвращает сколько реально добавлено.
function StatUpgradeHandler:GrantLevels(player, statKey: string, amount: number): number
	local cfg = StatUpgradesConfig.Stats[statKey]
	if not cfg then
		warn(`[StatUpgrade] неизвестный стат "{statKey}"`)
		return 0
	end

	if statKey == PRESS_SPEED then
		return Knit.GetService("PressService"):GrantSpeedLevels(player, amount)
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

	if statKey == PRESS_SPEED then
		return false -- за Money — PressService:BuySpeedUpgrade
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

	local step = StatUpgradesConfig.RobuxStepFor(statKey, currentLevel(player, statKey))
	if not step or step.ProductId == 0 then
		warn(`[StatUpgrade] платный продукт для "{statKey}" не задан в StatUpgradesConfig`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, step.ProductId)
end

function StatUpgradeHandler.Start()
	-- TODO: идемпотентность чеков (кэш обработанных receipt'ов в профиле),
	-- чтобы повторная обработка чека после падения сервера не выдала уровни дважды.
	-- каждая ступень — свой дев-продукт; уровни выдаёт ступень, чей ProductId купили
	for statKey in pairs(StatUpgradesConfig.Stats) do
		for _, step in ipairs(StatUpgradesConfig.RobuxSteps(statKey)) do
			if step.ProductId ~= 0 then
				MarketplaceReceiptRouter.Register(step.ProductId, function(player)
					StatUpgradeHandler:GrantLevels(player, statKey, step.Levels)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end)
			end
		end
	end
end

function StatUpgradeHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return StatUpgradeHandler
