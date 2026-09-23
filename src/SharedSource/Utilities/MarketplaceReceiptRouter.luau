local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

--[[
	MarketplaceReceiptRouter — единственный держатель MarketplaceService.ProcessReceipt
	на весь проект. ProcessReceipt можно назначить только ОДИН раз (повторное
	присваивание молча перетирает предыдущее) — если несколько систем донат-покупок
	(StatUpgradeHandler, AutoClickZone и т.д.) будут ставить его напрямую, реально
	будет работать только та, что назначила последней.

	Все системы регистрируются здесь вместо прямого назначения ProcessReceipt:
	  Register(productId, handler)  — productId известен заранее (из конфига).
	  RegisterFallback(handler)     — productId заранее не известен (например,
	                                  задаётся Attribute'ом на объекте в Workspace).
	                                  Фолбэки пробуются по очереди, пока кто-то
	                                  не вернёт decision.

	Только для Developer Product (ProcessReceipt). AutoClickZone монетизирован
	через Game Pass и через этот роутер не проходит — см.
	AutoClickZonePurchaseHandler (PromptGamePassPurchaseFinished, отдельный сигнал).

	handler(player, productId) -> Enum.ProductPurchaseDecision?
	  Fallback-хендлер возвращает nil, если это не его productId — тогда роутер
	  пробует следующий.
]]
local MarketplaceReceiptRouter = {}

local specificHandlers: { [number]: (Player, number) -> Enum.ProductPurchaseDecision? } = {}
local fallbackHandlers: { (Player, number) -> Enum.ProductPurchaseDecision? } = {}
local claimed = false

local function resolveDecision(handler, player, productId): Enum.ProductPurchaseDecision?
	local ok, decision = pcall(handler, player, productId)

	if not ok then
		warn("[MarketplaceReceiptRouter] ошибка в обработчике покупки:", decision)
		return nil
	end

	return decision
end

local function ensureClaimed()
	if claimed then
		return
	end
	claimed = true

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local specific = specificHandlers[receiptInfo.ProductId]
		if specific then
			local decision = resolveDecision(specific, player, receiptInfo.ProductId)
			return decision or Enum.ProductPurchaseDecision.NotProcessedYet
		end

		for _, fallback in ipairs(fallbackHandlers) do
			local decision = resolveDecision(fallback, player, receiptInfo.ProductId)
			if decision then
				return decision
			end
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function MarketplaceReceiptRouter.Register(
	productId: number,
	handler: (Player, number) -> Enum.ProductPurchaseDecision?
)
	if specificHandlers[productId] then
		warn("[MarketplaceReceiptRouter] productId уже зарегистрирован:", productId)
	end

	specificHandlers[productId] = handler
	ensureClaimed()
end

function MarketplaceReceiptRouter.RegisterFallback(handler: (Player, number) -> Enum.ProductPurchaseDecision?)
	table.insert(fallbackHandlers, handler)
	ensureClaimed()
end

-- Занят ли productId СПЕЦИФИЧНЫМ хендлером (Register, не RegisterFallback).
-- Специфичные хендлеры всегда выигрывают у фолбэков — полезно для диагностики
-- "мой fallback-продукт никогда не срабатывает": если id уже кем-то Register'нут
-- (например, случайно тот же id, что у баффа/апгрейда), fallback до него не дойдёт.
function MarketplaceReceiptRouter.IsRegistered(productId: number): boolean
	return specificHandlers[productId] ~= nil
end

return MarketplaceReceiptRouter
