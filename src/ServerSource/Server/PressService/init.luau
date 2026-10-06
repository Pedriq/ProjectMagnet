local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)
local PressMergeConfig = require(ReplicatedStorage.SharedSource.Datas.PressMergeConfig)

--[[
	PressService — гидравлический пресс (Workspace.HydraulicPress, см. PressConfig).

	Сервер — источник правды: сколько руды в прессе (profile.Press.Ores), что
	скрафчено и сколько денег начислено. Весь визуал (кусочки руды, предметы на
	конвейере) рисует PressController ТОЛЬКО у игрока, которому пришёл сигнал.

	Компоненты:
	  PressUnloadHandler — игрок встал на Unloading -> вся руда разом в пресс;
	  PressCraftHandler  — каждые OreConfig.WeightPerItem веса -> предмет -> продажа;
	                       деньги копятся в profile.Press.Unclaimed;
	  PressCollectHandler — игрок встал на Collect -> Unclaimed зачисляется в Money.
]]
local PressService = Knit.CreateService({
	Name = "PressService",
	Client = {
		-- Fire(player, ores) — вся руда разом выгружена с игрока в пресс,
		-- ores = map[oreId] = вес.
		OreUnloaded = Knit.CreateSignal(),
		-- Fire(player, oreId, weight, itemName?, rarity?, payout?) — пресс переработал
		-- `weight` руды oreId в предмет редкости rarity; деньги (payout, EtNum-строка)
		-- начислятся через PressConfig.SELL_DELAY. itemName == nil — остаток руды
		-- сгорел без предмета (см. PressConfig.RollRemainderRarity).
		ItemCrafted = Knit.CreateSignal(),
		-- Fire(player, amount) — игрок наступил на Collect и забрал накопленные
		-- деньги (amount — EtNum-строка). Сам остаток — profile.Press.Unclaimed.
		MoneyCollected = Knit.CreateSignal(),
		-- Fire(player, oreId) — игрок убрал всю руду oreId из пресса (табличка
		-- очереди, кнопка ✕), см. PressService:RemoveOre.
		OreRemoved = Knit.CreateSignal(),
		-- Fire(player, steps) — игрок объединил руду (Ore Merge): steps — список
		-- { From, To, Groups, Consumed, Produced } (PressMergeConfig.Plan). Клиент играет эффект.
		OreMerged = Knit.CreateSignal(),
		-- Fire(player, title, subtitle?) — короткое уведомление игроку (например, «Nothing to merge»).
		Notice = Knit.CreateSignal(),
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

	-- выгрузка руды = тир «достигнут» (Ore Merge не поднимается выше него)
	if weight > 0 then
		local index = table.find(OreConfig.Order, oreId)
		if index and index > self:GetStoredHighestOre(player) then
			ProfileService:ChangeData(player, { "Press", "HighestOre" }, index)
		end
	end
end

-- === Ore Merge (PressMergeConfig) ==============================================
function PressService:GetStoredHighestOre(player): number
	return math.max(math.floor(tonumber(ProfileService:GetData(player, { "Press", "HighestOre" })) or 1), 1)
end

function PressService:GetMergeLevel(player): number
	return PressMergeConfig.ClampLevel(ProfileService:GetData(player, { "Press", "MergeLevel" }))
end

-- Ручное объединение руды в прессе. oreId — только эта руда на один тир вверх;
-- nil — «Merge All» (все руды снизу вверх, результат каскадом идёт дальше).
-- Выше высшего достигнутого тира руда не создаётся. true — что-то объединилось.
function PressService:MergeOres(player, oreId: string?): boolean
	if not self:IsProfileLoaded(player) then
		return false
	end
	if oreId ~= nil and (type(oreId) ~= "string" or not OreConfig.Get(oreId)) then
		return false
	end

	local ores = {}
	for id, weight in pairs(self:GetPressOres(player)) do
		if type(weight) == "number" then
			ores[id] = weight
		end
	end

	local highest = PressMergeConfig.HighestIndex(self:GetStoredHighestOre(player), ores)
	local ratio = PressMergeConfig.GetRatio(self:GetMergeLevel(player))
	local newOres, steps = PressMergeConfig.Plan(ores, ratio, highest, oreId)
	if #steps == 0 then
		return false
	end

	-- рекорд тира сохраняем (очередь могла опустеть позже)
	if highest > self:GetStoredHighestOre(player) then
		ProfileService:ChangeData(player, { "Press", "HighestOre" }, highest)
	end
	-- ОДНА запись всей таблицы руды (а не по записи на каждую руду): один пакет репликации,
	-- одно событие на клиенте (PressController/Data обрабатывают путь Press/Ores без ключа руды)
	ProfileService:ChangeData(player, { "Press", "Ores" }, newOres)

	self.Client.OreMerged:Fire(player, steps)
	return true
end

function PressService.Client:MergeOre(player, oreId)
	return self.Server:MergeOres(player, oreId)
end

function PressService.Client:MergeAll(player)
	return self.Server:MergeOres(player, nil)
end

-- Прокачка «Merge Efficiency» за Money (Press Upgrade). true — куплено.
function PressService:BuyMergeUpgrade(player): boolean
	if not self:IsProfileLoaded(player) then
		return false
	end
	local level = self:GetMergeLevel(player)
	local cost = PressMergeConfig.UpgradeCost(level)
	if not cost then
		return false -- максимум
	end

	local money = ProfileService:GetData(player, { "Stats", "Money" }) or "0"
	if EtNum.me(cost, money) then -- цена > денег
		return false
	end

	ProfileService:ChangeData(player, { "Stats", "Money" }, EtNum.toString(EtNum.sub(money, cost)))
	ProfileService:ChangeData(player, { "Press", "MergeLevel" }, level + 1)
	return true
end

function PressService.Client:BuyMergeUpgrade(player)
	return self.Server:BuyMergeUpgrade(player)
end

-- Деньги за проданные прессом предметы, ещё не забранные на Collect (EtNum-строка).
function PressService:GetUnclaimed(player)
	return ProfileService:GetData(player, { "Press", "Unclaimed" }) or "0"
end

function PressService:SetUnclaimed(player, amount: string)
	ProfileService:ChangeData(player, { "Press", "Unclaimed" }, amount)
end

function PressService:AddUnclaimed(player, amount)
	self:SetUnclaimed(player, EtNum.toString(EtNum.add(amount, self:GetUnclaimed(player))))
end

-- Все BasePart'ы детей HydraulicPress с именем из `names` (сама деталь или
-- части модели с таким именем).
--
-- Модель зоны (например Unloading: ZoneDashedOutline + ZoneFloor, см. README/
-- PressUnloadHandler) детектит игрока СТРОГО по ZoneFloor — не по всем BasePart
-- внутри, иначе в детект попал бы декоративный вращающийся ZoneDashedOutline.
-- Если ZoneFloor нет (старые/другие зоны без такой структуры) — падаем назад на
-- поиск по всем BasePart, как раньше.
function PressService:GetPadParts(names: { string }): { BasePart }
	local press = workspace:FindFirstChild(PressConfig.PRESS_NAME)
	local parts = {}
	if not press then
		return parts
	end

	for _, child in ipairs(press:GetChildren()) do
		if table.find(names, child.Name) then
			if child:IsA("BasePart") then
				table.insert(parts, child)
			else
				local floor = child:FindFirstChild("ZoneFloor")
				if floor and floor:IsA("BasePart") then
					table.insert(parts, floor)
				else
					for _, d in ipairs(child:GetDescendants()) do
						if d:IsA("BasePart") then
							table.insert(parts, d)
						end
					end
				end
			end
		end
	end
	return parts
end

-- Игроки (с загруженным профилем), чей HumanoidRootPart сейчас над площадкой
-- с именем из `names`.
function PressService:GetPlayersOnPads(names: { string }): { [Player]: boolean }
	local onPad = {}
	local pads = self:GetPadParts(names)
	if #pads == 0 then
		return onPad
	end

	local roots = {}
	local rootToPlayer = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and self:IsProfileLoaded(player) then
			table.insert(roots, root)
			rootToPlayer[root] = player
		end
	end
	if #roots == 0 then
		return onPad
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots

	for _, pad in ipairs(pads) do
		-- Площадка обычно плоская плита на полу, а HumanoidRootPart висит ~3 studs
		-- над ней и с самой плитой не пересекается — поэтому проверяем объём,
		-- вытянутый вверх от плиты на PAD_CHECK_HEIGHT.
		local height = PressConfig.PAD_CHECK_HEIGHT
		local boxCFrame = pad.CFrame * CFrame.new(0, height / 2, 0)
		local boxSize = Vector3.new(pad.Size.X, pad.Size.Y + height, pad.Size.Z)
		for _, part in ipairs(workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)) do
			local player = rootToPlayer[part]
			if player then
				onPad[player] = true
			end
		end
	end
	return onPad
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
		Unclaimed = self:GetUnclaimed(player),
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

-- Убрать из пресса ВСЮ руду oreId (управление очередью: пресс крафтит руды по
-- порядку OreConfig.Order, начиная с дешёвых — игрок может выкинуть дешёвую руду,
-- чтобы дорогая пошла в работу сразу). Руда уничтожается, не возвращается.
-- Уже начатый предмет (вес списан в _Craft) не отменяется.
function PressService:RemoveOre(player, oreId): boolean
	if type(oreId) ~= "string" or not OreConfig.Get(oreId) or not self:IsProfileLoaded(player) then
		return false
	end
	local weight = tonumber(self:GetPressOres(player)[oreId]) or 0
	if weight <= 0 then
		return false
	end

	ProfileService:ChangeData(player, { "Press", "Ores", oreId }, nil)
	self.Client.OreRemoved:Fire(player, oreId)
	return true
end

function PressService.Client:RemoveOre(player, oreId)
	return self.Server:RemoveOre(player, oreId)
end

-- Прокачка скорости пресса (profile.Press.CraftSpeed) на 1 уровень за Money.
-- Цена — общая формула статов (StatUpgradesConfig.CostFor("PressSpeed", level)).
-- Уровень продаётся до StatUpgradesConfig.Stats.PressSpeed.MaxLevel, но реальная
-- скорость перестаёт расти после PressConfig.CRAFT_MAX_EFFECTIVE_LEVEL (потолок
-- PressConfig.MAX_ITEMS_PER_SECOND) — см. PressConfig.GetCraftItemsPerSecond.
-- true — куплено, false — нет денег / максимум / профиль не загружен.
function PressService:BuySpeedUpgrade(player): boolean
	if not self:IsProfileLoaded(player) then
		return false
	end

	local cfg = StatUpgradesConfig.Stats.PressSpeed
	local level = self:GetPressLevel(player, "CraftSpeed")
	if level >= cfg.MaxLevel then
		return false
	end

	local cost = StatUpgradesConfig.CostFor("PressSpeed", level)
	local money = ProfileService:GetData(player, { "Stats", "Money" }) or "0"
	if EtNum.me(cost, money) then -- цена > денег
		return false
	end

	ProfileService:ChangeData(player, { "Stats", "Money" }, EtNum.toString(EtNum.sub(money, cost)))
	ProfileService:ChangeData(player, { "Press", "CraftSpeed" }, level + 1)
	return true
end

-- Платный skip (дев-продукт, StatUpgradeHandler): +amount уровней CraftSpeed без списания
-- денег, с потолком MaxLevel. Возвращает сколько уровней реально добавлено.
function PressService:GrantSpeedLevels(player, amount: number): number
	if not self:IsProfileLoaded(player) then
		return 0
	end
	local level = self:GetPressLevel(player, "CraftSpeed")
	local newLevel = math.clamp(level + amount, level, StatUpgradesConfig.Stats.PressSpeed.MaxLevel)
	if newLevel == level then
		return 0
	end
	ProfileService:ChangeData(player, { "Press", "CraftSpeed" }, newLevel)
	return newLevel - level
end

function PressService.Client:BuySpeedUpgrade(player)
	return self.Server:BuySpeedUpgrade(player)
end

function PressService:KnitStart()
	self.Components.PressUnloadHandler:StartWatching()
	self.Components.PressCraftHandler:StartCrafting()
	self.Components.PressCollectHandler:StartWatching()
	self.Components.PressMergeHandler:StartWatching()
end

function PressService:KnitInit()
	ProfileService = Knit.GetService("ProfileService")

	---- Components Initializer
	componentsInitializer(script)
end

return PressService
