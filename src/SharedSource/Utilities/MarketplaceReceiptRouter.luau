local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Идемпотентность чеков: Roblox может доставить один и тот же чек повторно (сервер упал после выдачи, но до
-- сохранения профиля). Выданные PurchaseId лежат в profile.Receipts; повторный чек сразу закрывается как
-- выданный, без повторной выдачи. Хранится не больше RECEIPT_KEEP последних записей (профиль не раздувается).
local RECEIPT_KEEP = 200
local inFlight: { [string]: boolean } = {} -- чек обрабатывается прямо сейчас (хендлер может yield-ить)

local function profileFor(player: Player): any
	local ok, ProfileService = pcall(function()
		return require(ReplicatedStorage.Packages.Knit).GetService("ProfileService")
	end)
	local profile = ok and ProfileService.Profiles[player]
	return profile and profile.Data
end

local function pruneReceipts(receipts: { [string]: number })
	local count = 0
	for _ in pairs(receipts) do
		count += 1
	end
	if count <= RECEIPT_KEEP then
		return
	end

	local ids = {}
	for id in pairs(receipts) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return receipts[a] < receipts[b]
	end)
	for i = 1, count - RECEIPT_KEEP do
		receipts[ids[i]] = nil
	end
end

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

		-- без загруженного профиля не выдаём: не к чему записать ни товар, ни факт выдачи
		local data = profileFor(player)
		if not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if type(data.Receipts) ~= "table" then
			data.Receipts = {}
		end

		local purchaseKey = tostring(receiptInfo.PurchaseId)
		if data.Receipts[purchaseKey] then
			return Enum.ProductPurchaseDecision.PurchaseGranted -- уже выдано раньше
		end
		if inFlight[purchaseKey] then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- параллельная доставка того же чека
		end
		inFlight[purchaseKey] = true

		local decision: Enum.ProductPurchaseDecision? = nil
		local specific = specificHandlers[receiptInfo.ProductId]
		if specific then
			decision = resolveDecision(specific, player, receiptInfo.ProductId)
		else
			for _, fallback in ipairs(fallbackHandlers) do
				decision = resolveDecision(fallback, player, receiptInfo.ProductId)
				if decision then
					break
				end
			end
		end

		inFlight[purchaseKey] = nil

		if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
			-- записываем сразу после выдачи (напрямую в данные профиля — клиенту это знать не нужно)
			data.Receipts[purchaseKey] = os.time()
			pruneReceipts(data.Receipts)
		end

		return decision or Enum.ProductPurchaseDecision.NotProcessedYet
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
