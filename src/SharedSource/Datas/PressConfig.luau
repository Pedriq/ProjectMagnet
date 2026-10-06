local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)

--[[
	PressConfig — гидравлический пресс (Workspace.HydraulicPress).

	Игрок встаёт на Unloading -> вся руда из его инвентаря разом уходит в
	PressInventory. Каждые GetWeightPerItem(руда) веса одной руды пресс делает предмет
	редкости этой руды (OreConfig.Rarity -> TreasuresConfig), предмет едет по
	Conveyor, падает в Sell и продаётся.

	Две характеристики пресса (уровни в profile.Press):
	  UnloadSpeed — сейчас не используется (выгрузка мгновенная);
	  CraftSpeed  — как быстро пресс делает предметы.
	CraftSpeed прокачивается за Money (PressService:BuySpeedUpgrade, цена —
	StatUpgradesConfig.CostFor("PressSpeed", уровень), та же формула, что у статов).
	UnloadSpeed прокачки нет.
]]

local PressConfig = {}

PressConfig.PRESS_NAME = "HydraulicPress"
-- Площадки внутри HydraulicPress (по имени детали/модели).
PressConfig.UNLOADING_NAMES = { "Unloading" }
PressConfig.COLLECT_NAMES = { "Collect", "Cellect" }
-- Площадка Ore Merge: касание объединяет руду в очереди (PressMergeHandler).
PressConfig.MERGE_NAMES = { "Merge" }
-- Высота зоны над площадкой, в которой должен оказаться HumanoidRootPart.
PressConfig.PAD_CHECK_HEIGHT = 8

-- Сколько веса руды oreId уходит на один предмет (у каждой руды свой, см.
-- OreConfig.WeightPerItem: Common — 100, дальше тяжелее).
function PressConfig.GetWeightPerItem(oreId: string): number
	local ore = OreConfig.Get(oreId)
	return if ore then ore.WeightPerItem else math.huge
end

-- === UnloadSpeed: секунд на один кусочек руды
local BASE_UNLOAD_INTERVAL = 0.15
local UNLOAD_SPEED_PER_LEVEL = 0.25 -- +25% скорости за уровень

-- === CraftSpeed: сколько предметов в секунду делает пресс.
-- Уровень 1 — BASE_ITEMS_PER_SECOND, уровень CRAFT_MAX_EFFECTIVE_LEVEL — ровно
-- MAX_ITEMS_PER_SECOND; между ними — геометрически (каждый уровень даёт одинаковый
-- +% скорости, т.е. КАЖДЫЙ уровень до потолка реально ускоряет пресс).
-- Выше CRAFT_MAX_EFFECTIVE_LEVEL уровень растёт (и продаётся) дальше, но скорость
-- остаётся на потолке — «фейковая» прогрессия. MAX_ITEMS_PER_SECOND не
-- превышается ни при каком уровне (clamp уровня + math.min + max интервала).
local BASE_ITEMS_PER_SECOND = 0.5 -- = прежние 2 сек на предмет
local MAX_ITEMS_PER_SECOND = 5
local CRAFT_MAX_EFFECTIVE_LEVEL = 50

PressConfig.MAX_ITEMS_PER_SECOND = MAX_ITEMS_PER_SECOND
PressConfig.CRAFT_MAX_EFFECTIVE_LEVEL = CRAFT_MAX_EFFECTIVE_LEVEL

function PressConfig.GetCraftItemsPerSecond(level: number?): number
	local effective = math.clamp(math.floor(tonumber(level) or 1), 1, CRAFT_MAX_EFFECTIVE_LEVEL)
	local t = (effective - 1) / (CRAFT_MAX_EFFECTIVE_LEVEL - 1)
	local speed = BASE_ITEMS_PER_SECOND * (MAX_ITEMS_PER_SECOND / BASE_ITEMS_PER_SECOND) ^ t
	return math.min(speed, MAX_ITEMS_PER_SECOND)
end

function PressConfig.GetUnloadInterval(level: number?): number
	return BASE_UNLOAD_INTERVAL / (1 + (math.max(level or 1, 1) - 1) * UNLOAD_SPEED_PER_LEVEL)
end

-- Секунд на один предмет — никогда не меньше 1 / MAX_ITEMS_PER_SECOND.
function PressConfig.GetCraftInterval(level: number?): number
	return math.max(1 / PressConfig.GetCraftItemsPerSecond(level), 1 / MAX_ITEMS_PER_SECOND)
end

-- === Тайминги визуала. Сервер начисляет деньги через SELL_DELAY после крафта —
-- ровно когда у клиента предмет падает в Sell, поэтому клиент берёт длительности
-- анимации отсюда же.
PressConfig.SLAM_TIME = 0.25 -- головка пресса опускается и бьёт по руде
PressConfig.PRESS_TIME = 0.35 -- предмет «выдавливается» из PressInventory
PressConfig.CONVEYOR_TIME = 2.5 -- едет по конвейеру
PressConfig.FALL_TIME = 0.45 -- падает с конвейера в Sell
PressConfig.SELL_DELAY = PressConfig.SLAM_TIME
	+ PressConfig.PRESS_TIME
	+ PressConfig.CONVEYOR_TIME
	+ PressConfig.FALL_TIME

-- === Остаток руды (< веса на предмет). Когда игрок закончил выгрузку (с последнего
-- кусочка прошло REMAINDER_DELAY сек) и руды на целый предмет не хватает, из остатка
-- всё равно делается предмет: с шансом остаток / вес на предмет — редкости руды,
-- иначе — на одну редкость ниже. Для самой низкой редкости «ниже» нет — остаток
-- сгорает без предмета (иначе 10 веса Common давали бы столько же, сколько 100).
PressConfig.REMAINDER_DELAY = 1.5

-- Порядок редкостей от низшей к высшей (ключи TreasuresConfig).
PressConfig.RARITY_ORDER = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Secret",
	"Godly",
	"Divine",
	"Celestial",
	"Eternal",
	"Cosmic",
	"Ascendant",
}

-- Редкость предмета из остатка `weight` руды редкости `rarity` (на целый предмет нужно
-- `weightPerItem`); nil — предмета не будет.
function PressConfig.RollRemainderRarity(rarity: string, weight: number, weightPerItem: number): string?
	local chance = math.clamp(weight / weightPerItem, 0, 1)
	if math.random() < chance then
		return rarity
	end

	local index = table.find(PressConfig.RARITY_ORDER, rarity)
	for i = (index or 1) - 1, 1, -1 do
		local lower = PressConfig.RARITY_ORDER[i]
		if TreasuresConfig[lower] and #TreasuresConfig[lower] > 0 then
			return lower
		end
	end
	return nil
end

-- Случайный предмет редкости `rarity` (ItemsConfig = TreasuresConfig). nil — если
-- для редкости нет предметов.
function PressConfig.RollItem(rarity: string): { Name: string, Price: string }?
	local items = TreasuresConfig[rarity]
	if not items or #items == 0 then
		return nil
	end
	return items[math.random(1, #items)]
end

return PressConfig
