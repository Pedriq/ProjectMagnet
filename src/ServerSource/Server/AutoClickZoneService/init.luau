local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoClickZoneService = Knit.CreateService({
	Name = "AutoClickZoneService",
	Client = {
		-- Fire(player, text) — показать игроку красное предупреждение (например "Not Enough Yet").
		ShowMessage = Knit.CreateSignal(),
		-- Fire(player, teslaCoil, gain?) — проиграть визуальный эффект пульсации катушки Теслы зоны;
		-- gain — прирост силы за этот автоклик (EtNum-строка) для числа над персонажем.
		ZonePulse = Knit.CreateSignal(),
		-- Fire(player, zoneId) — зона куплена (наступил ИЛИ через Shop), см.
		-- AutoClickZonePurchaseHandler.Start (ProcessReceipt). Обновляет "Owned" в панели Shop.
		ZonePurchased = Knit.CreateSignal(),
	},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
AutoClickZoneService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	AutoClickZoneService.Components[v.Name] = require(v)
end
AutoClickZoneService.GetComponent = require(componentsFolder["Get()"])
AutoClickZoneService.SetComponent = require(componentsFolder["Set()"])

-- Каталог автоклик-зон для панели Shop (Training Zones): по одной карточке на
-- ZoneId, с флагом Purchased для этого игрока — см. AutoClickZonePurchaseHandler.
function AutoClickZoneService:GetZoneCatalog(player)
	return self.Components.AutoClickZonePurchaseHandler:GetCatalog(player)
end

function AutoClickZoneService.Client:GetZoneCatalog(player)
	return self.Server:GetZoneCatalog(player)
end

-- Клиент жмёт «купить» на карточке зоны в Shop: присылает ТОЛЬКО ZoneId,
-- сервер сам находит модель зоны и её gamePassId (клиент не выбирает
-- gamePassId напрямую) и открывает промпт покупки, если зона ещё не куплена.
function AutoClickZoneService:PromptZonePurchase(player, zoneId)
	self.Components.AutoClickZonePurchaseHandler:PromptValidatedPurchase(player, zoneId)
end

function AutoClickZoneService.Client:PromptZonePurchase(player, zoneId)
	self.Server:PromptZonePurchase(player, zoneId)
end

function AutoClickZoneService:KnitStart() end

function AutoClickZoneService:KnitInit()
	---- Components Initializer
	componentsInitializer(script)
end

return AutoClickZoneService
