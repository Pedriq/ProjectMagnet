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
	каждая покупка просто добавляет к текущей силе PowerPackConfig.GrantFor(пак, мир
	игрока), БЕЗ множителей (rebirth/бафф/донат) — так попросил заказчик. Мир
	фиксируется в момент промпта, чтобы начислилось ровно то, что было на кнопке.
]]
local PowerPackPurchaseHandler = {}

---- Knit Services
local ClickerService
local PlayerManagerService

-- [userId] = { [productId] = world } — мир, который игрок видел на кнопке при промпте.
local promptedWorld = {}

function PowerPackPurchaseHandler:PromptPurchase(player: Player, productId: number)
	if not PowerPackConfig.ByProductId(productId) then
		warn(`[PowerPackPurchase] неизвестный productId: {productId}`)
		return
	end

	promptedWorld[player.UserId] = promptedWorld[player.UserId] or {}
	promptedWorld[player.UserId][productId] = PlayerManagerService:GetPlayerWorld(player)

	MarketplaceService:PromptProductPurchase(player, productId)
end

-- Начислить пак: сложение + левел-ап при пересечении порога — та же логика,
-- что ClickHandler:Click (продублирована намеренно: тут нет ни оружия, ни
-- множителя, только прибавление готовой суммы MagnetismGrant).
function PowerPackPurchaseHandler:Grant(player: Player, pack: PowerPackConfig.Pack)
	-- мир с момента промпта; нет записи (чек обработан после перезахода) — текущий мир
	local prompted = promptedWorld[player.UserId]
	local world = prompted and prompted[pack.ProductId] or PlayerManagerService:GetPlayerWorld(player)
	if prompted then
		prompted[pack.ProductId] = nil
	end
	local grant = PowerPackConfig.GrantFor(pack, world)

	local magnetism = ClickerService:GetPlayerMagnetism(player) or "0"
	local newMagnetism = EtNum.add(magnetism, grant)

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
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		promptedWorld[player.UserId] = nil
	end)
end

return PowerPackPurchaseHandler
