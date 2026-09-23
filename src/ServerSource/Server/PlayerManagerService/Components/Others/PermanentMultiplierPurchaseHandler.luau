local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PermanentMultiplierConfig = require(ReplicatedStorage.SharedSource.Datas.PermanentMultiplierConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	PermanentMultiplierPurchaseHandler — покупка постоянных множителей (HUD ->
	BuffBuyButton) за донат. productId'ы известны заранее
	(PermanentMultiplierConfig.Tiers), поэтому регистрируемся в
	MarketplaceReceiptRouter как specific-хендлеры (как BuffPurchaseHandler /
	StatUpgradeHandler), не как fallback.
]]
local PermanentMultiplierPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

function PermanentMultiplierPurchaseHandler:PromptPurchase(player: Player, productId: number)
	local buffType = PermanentMultiplierConfig.ByProductId(productId)
	if not buffType then
		warn(`[PermanentMultiplierPurchase] неизвестный productId: {productId}`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

function PermanentMultiplierPurchaseHandler.Start()
	for buffType, tiers in pairs(PermanentMultiplierConfig.Tiers) do
		for _, tier in ipairs(tiers) do
			MarketplaceReceiptRouter.Register(tier.ProductId, function(player)
				PlayerManagerService.Components.PermanentMultiplierHandler:Grant(player, buffType, tier)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end)
		end
	end
end

function PermanentMultiplierPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PermanentMultiplierPurchaseHandler
