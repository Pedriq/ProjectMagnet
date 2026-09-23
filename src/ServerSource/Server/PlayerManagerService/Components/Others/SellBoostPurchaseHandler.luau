local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local SellBoostConfig = require(ReplicatedStorage.SharedSource.Datas.SellBoostConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	SellBoostPurchaseHandler — донат-продукт "Sell x2" (панель Sell Loot,
	кнопка рядом с Sell All). Покупка НЕ ЗАПРАШИВАЕТСЯ отдельно — сразу
	продаёт весь текущий инвентарь лута с доп. x2 к цене (см. SellBoostConfig).

	Один productId, без ступеней/владения — покупать можно сколько угодно раз.
]]
local SellBoostPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

function SellBoostPurchaseHandler:PromptPurchase(player: Player)
	MarketplaceService:PromptProductPurchase(player, SellBoostConfig.ProductId)
end

function SellBoostPurchaseHandler.Start()
	MarketplaceReceiptRouter.Register(SellBoostConfig.ProductId, function(player)
		PlayerManagerService.Components.PlayerTreasureManager:SellAllItems(player, SellBoostConfig.Multiplier)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
end

function SellBoostPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return SellBoostPurchaseHandler
