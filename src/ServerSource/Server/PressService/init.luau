local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)

--[[
	PressService — гидравлический пресс (Workspace.HydraulicPress, см. PressConfig).

	Сервер — источник правды: сколько руды в прессе (profile.Press.Ores), что
	скрафчено и сколько денег начислено. Весь визуал (кусочки руды, предметы на
	конвейере) рисует PressController ТОЛЬКО у игрока, которому пришёл сигнал.

	Компоненты:
	  PressUnloadHandler — игрок стоит на Unloading -> руда по кусочку в пресс;
	  PressCraftHandler  — каждые WEIGHT_PER_ITEM веса -> предмет -> продажа.
]]
local PressService = Knit.CreateService({
	Name = "PressService",
	Client = {
		-- Fire(player, oreId, weight) — кусочек руды выгружен с игрока в пресс.
		OreUnloaded = Knit.CreateSignal(),
		-- Fire(player, oreId, weight, itemName?, rarity?, payout?) — пресс переработал
		-- `weight` руды oreId в предмет редкости rarity; деньги (payout, EtNum-строка)
		-- начислятся через PressConfig.SELL_DELAY. itemName == nil — остаток руды
		-- сгорел без предмета (см. PressConfig.RollRemainderRarity).
		ItemCrafted = Knit.CreateSignal(),
	},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
PressService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	PressService.Components[v.Name] = require(v)
end
PressService.GetComponent = require(componentsFolder["Get()"])
PressService.SetComponent = require(componentsFolder["Set()"])

---- Knit Services
local ProfileService

-- Профиль игрока уже загружен? ProfileService:GetData до загрузки ЖДЁТ профиль —
-- в общих циклах пресса так нельзя, поэтому такие игроки просто пропускаются.
function PressService:IsProfileLoaded(player)
	return ProfileService.Profiles[player] ~= nil
end

-- Руда в прессе: map[oreId] = вес.
function PressService:GetPressOres(player)
	return ProfileService:GetData(player, { "Press", "Ores" }) or {}
end

function PressService:AddPressOre(player, oreId, weight)
	local current = tonumber(self:GetPressOres(player)[oreId]) or 0
	local newWeight = current + weight
	ProfileService:ChangeData(player, { "Press", "Ores", oreId }, if newWeight > 0 then newWeight else nil)
end

-- Уровень характеристики пресса: "UnloadSpeed" | "CraftSpeed".
function PressService:GetPressLevel(player, stat)
	return tonumber(ProfileService:GetData(player, { "Press", stat })) or 1
end

function PressService:GetState(player)
	local ores = {}
	for oreId, weight in pairs(self:GetPressOres(player)) do
		if type(weight) == "number" then
			ores[oreId] = weight
		end
	end

	local unloadLevel = self:GetPressLevel(player, "UnloadSpeed")
	local craftLevel = self:GetPressLevel(player, "CraftSpeed")
	return {
		Ores = ores,
		UnloadSpeed = unloadLevel,
		CraftSpeed = craftLevel,
		UnloadInterval = PressConfig.GetUnloadInterval(unloadLevel),
		CraftInterval = PressConfig.GetCraftInterval(craftLevel),
	}
end

-- Снапшот при старте клиента: руда, уже лежащая в прессе (для визуала кучки), и статы.
function PressService.Client:GetState(player)
	return self.Server:GetState(player)
end

function PressService:KnitStart()
	self.Components.PressUnloadHandler:StartWatching()
	self.Components.PressCraftHandler:StartCrafting()
end

function PressService:KnitInit()
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)
end

return PressService
