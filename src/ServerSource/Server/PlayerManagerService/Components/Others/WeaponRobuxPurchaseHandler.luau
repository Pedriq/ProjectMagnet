local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	WeaponRobuxPurchaseHandler — покупка обычных мечей «Cutters» за Robux, в
	обход цены Money (WeaponData[key].RobuxProductId). НЕ путать с
	WeaponGamePassPurchaseHandler: там донат-мечи (Wraithflame/WarringWingblade,
	"OP Swords") продаются ТОЛЬКО за Game Pass и вообще не продаются за Money;
	тут же — обычные мечи из WeaponData.Order, для которых Robux — просто более
	быстрый путь вместо накопления Money.

	Дев-продукт (не Game Pass) — регистрируемся в MarketplaceReceiptRouter, как
	и остальные дев-продукты в проекте. Покупка сразу выдаёт владение и
	экипирует — как и покупка за Money (WeaponShopHandler:BuyWithMoney).
]]
local WeaponRobuxPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

-- productId -> внутренний ключ меча (WeaponData[key].RobuxProductId).
local function robuxWeapons(): { [number]: string }
	local map = {}
	for _, name in ipairs(WeaponData.Order) do
		local cfg = WeaponData[name]
		if cfg.RobuxProductId then
			map[cfg.RobuxProductId] = name
		end
	end
	return map
end

function WeaponRobuxPurchaseHandler:PromptPurchase(player: Player, weaponName: string)
	local cfg = weaponName and WeaponData[weaponName]
	if not cfg or not cfg.RobuxProductId then
		warn(`[WeaponRobuxPurchase] "{tostring(weaponName)}" не продаётся за Robux (нет RobuxProductId)`)
		return
	end

	if PlayerManagerService.Components.WeaponShopHandler:Owns(player, weaponName) then
		return
	end

	MarketplaceService:PromptProductPurchase(player, cfg.RobuxProductId)
end

function WeaponRobuxPurchaseHandler.Start()
	for productId, weaponName in pairs(robuxWeapons()) do
		MarketplaceReceiptRouter.Register(productId, function(player)
			local weaponShopHandler = PlayerManagerService.Components.WeaponShopHandler
			if not weaponShopHandler:Owns(player, weaponName) then
				PlayerManagerService:SetWeaponOwned(player, weaponName)
				weaponShopHandler:EquipWeapon(player, weaponName)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end)
	end
end

function WeaponRobuxPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return WeaponRobuxPurchaseHandler
