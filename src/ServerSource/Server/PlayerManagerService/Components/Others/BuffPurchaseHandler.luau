local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local BuffConfig = require(ReplicatedStorage.SharedSource.Datas.BuffConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	BuffPurchaseHandler — покупка временных баффов (панель Shop -> Boosts) за
	донат. productId'ы известны заранее (BuffConfig.Boosts), поэтому
	регистрируемся в MarketplaceReceiptRouter как specific-хендлеры (как
	StatUpgradeHandler), не как fallback.
]]
local BuffPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

function BuffPurchaseHandler:PromptPurchase(player: Player, productId: number)
	if not BuffConfig.ByProductId(productId) then
		warn(`[BuffPurchase] неизвестный productId для баффа: {productId}`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

function BuffPurchaseHandler.Start()
	for _, entry in ipairs(BuffConfig.Boosts) do
		MarketplaceReceiptRouter.Register(entry.ProductId, function(player)
			PlayerManagerService.Components.BuffHandler:Grant(player, entry.Type, entry.Minutes * 60, entry.Bonus)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end)
	end
end

function BuffPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return BuffPurchaseHandler
