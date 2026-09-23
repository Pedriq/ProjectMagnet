local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	MagnetRobuxPurchaseHandler — покупка обычных мечей «Cutters» за Robux, в
	обход цены Money (MagnetData[key].RobuxProductId). НЕ путать с
	MagnetGamePassPurchaseHandler: там донат-мечи (Wraithflame/WarringWingblade,
	"OP Magnets") продаются ТОЛЬКО за Game Pass и вообще не продаются за Money;
	тут же — обычные мечи из MagnetData.Order, для которых Robux — просто более
	быстрый путь вместо накопления Money.

	Дев-продукт (не Game Pass) — регистрируемся в MarketplaceReceiptRouter, как
	и остальные дев-продукты в проекте. Покупка сразу выдаёт владение и
	экипирует — как и покупка за Money (MagnetShopHandler:BuyWithMoney).
]]
local MagnetRobuxPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

-- productId -> внутренний ключ меча (MagnetData[key].RobuxProductId).
local function robuxMagnets(): { [number]: string }
	local map = {}
	for _, name in ipairs(MagnetData.Order) do
		local cfg = MagnetData[name]
		if cfg.RobuxProductId then
			map[cfg.RobuxProductId] = name
		end
	end
	return map
end

function MagnetRobuxPurchaseHandler:PromptPurchase(player: Player, magnetName: string)
	local cfg = magnetName and MagnetData[magnetName]
	if not cfg or not cfg.RobuxProductId then
		warn(`[MagnetRobuxPurchase] "{tostring(magnetName)}" не продаётся за Robux (нет RobuxProductId)`)
		return
	end

	if PlayerManagerService.Components.MagnetShopHandler:Owns(player, magnetName) then
		return
	end

	MarketplaceService:PromptProductPurchase(player, cfg.RobuxProductId)
end

function MagnetRobuxPurchaseHandler.Start()
	for productId, magnetName in pairs(robuxMagnets()) do
		MarketplaceReceiptRouter.Register(productId, function(player)
			local magnetShopHandler = PlayerManagerService.Components.MagnetShopHandler
			if not magnetShopHandler:Owns(player, magnetName) then
				PlayerManagerService:SetMagnetOwned(player, magnetName)
				magnetShopHandler:EquipMagnet(player, magnetName)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end)
	end
end

function MagnetRobuxPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return MagnetRobuxPurchaseHandler
