local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local LevelCurve = require(ReplicatedStorage.SharedSource.Datas.LevelCurve)
local PowerPackConfig = require(ReplicatedStorage.SharedSource.Datas.PowerPackConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)

--[[
	PowerPackPurchaseHandler — разовая покупка силы за донат (HUD -> PowerBuyButton).
	productId'ы известны заранее (PowerPackConfig.Packs), регистрируемся в
	MarketplaceReceiptRouter как specific-хендлеры (как BuffPurchaseHandler /
	PermanentMultiplierPurchaseHandler).

	В отличие от PermanentMultiplierPurchaseHandler — тут нет ступеней/owned:
	каждая покупка просто добавляет PowerPackConfig.Packs[i].MagnetismGrant к
	текущей силе, БЕЗ множителей (rebirth/бафф/донат) — так попросил заказчик.
]]
local PowerPackPurchaseHandler = {}

---- Knit Services
local ClickerService

function PowerPackPurchaseHandler:PromptPurchase(player: Player, productId: number)
	if not PowerPackConfig.ByProductId(productId) then
		warn(`[PowerPackPurchase] неизвестный productId: {productId}`)
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

-- Начислить пак: сложение + левел-ап при пересечении порога — та же логика,
-- что ClickHandler:Click (продублирована намеренно: тут нет ни оружия, ни
-- множителя, только прибавление готовой суммы MagnetismGrant).
function PowerPackPurchaseHandler:Grant(player: Player, pack: PowerPackConfig.Pack)
	local magnetism = ClickerService:GetPlayerMagnetism(player) or "0"
	local newMagnetism = EtNum.add(magnetism, pack.MagnetismGrant)

	local currentLevel = ClickerService:GetPlayerLevel(player)
	local leveledUp = false
	while EtNum.meeq(newMagnetism, LevelCurve.TotalForLevel(currentLevel + 1)) do
		currentLevel += 1
		leveledUp = true
	end
	if leveledUp then
		ClickerService:ChangePlayerLevel(player, currentLevel)
	end

	ClickerService:ChangePlayerMagnetism(player, EtNum.toString(newMagnetism))
end

function PowerPackPurchaseHandler.Start()
	for _, pack in ipairs(PowerPackConfig.Packs) do
		MarketplaceReceiptRouter.Register(pack.ProductId, function(player)
			PowerPackPurchaseHandler:Grant(player, pack)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end)
	end
end

function PowerPackPurchaseHandler.Init()
	ClickerService = Knit.GetService("ClickerService")
end

return PowerPackPurchaseHandler
