local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)

--[[
	PressConfig — гидравлический пресс (Workspace.HydraulicPress).

	Игрок стоит на Unloading -> руда из его инвентаря по кусочку улетает в
	PressInventory. Каждые WEIGHT_PER_ITEM веса одной руды пресс делает предмет
	редкости этой руды (OreConfig.Rarity -> TreasuresConfig), предмет едет по
	Conveyor, падает в Sell и продаётся.

	Две характеристики пресса (уровни в profile.Press):
	  UnloadSpeed — как быстро руда выгружается с игрока;
	  CraftSpeed  — как быстро пресс делает предметы.
	Прокачки пока нет — уровни всегда 1, формулы ниже уже учитывают уровень.
]]

local PressConfig = {}

-- Сколько веса одной руды уходит на один предмет.
PressConfig.WEIGHT_PER_ITEM = 100

-- === UnloadSpeed: секунд на один кусочек руды
local BASE_UNLOAD_INTERVAL = 0.15
local UNLOAD_SPEED_PER_LEVEL = 0.25 -- +25% скорости за уровень

-- === CraftSpeed: секунд на один предмет
local BASE_CRAFT_INTERVAL = 2
local CRAFT_SPEED_PER_LEVEL = 0.25

function PressConfig.GetUnloadInterval(level: number?): number
	return BASE_UNLOAD_INTERVAL / (1 + (math.max(level or 1, 1) - 1) * UNLOAD_SPEED_PER_LEVEL)
end

function PressConfig.GetCraftInterval(level: number?): number
	return BASE_CRAFT_INTERVAL / (1 + (math.max(level or 1, 1) - 1) * CRAFT_SPEED_PER_LEVEL)
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

-- === Остаток руды (< WEIGHT_PER_ITEM). Когда игрок закончил выгрузку (с последнего
-- кусочка прошло REMAINDER_DELAY сек) и руды на целый предмет не хватает, из остатка
-- всё равно делается предмет: с шансом weight / WEIGHT_PER_ITEM — редкости руды,
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

-- Редкость предмета из остатка `weight` руды редкости `rarity`; nil — предмета не будет.
function PressConfig.RollRemainderRarity(rarity: string, weight: number): string?
	local chance = math.clamp(weight / PressConfig.WEIGHT_PER_ITEM, 0, 1)
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
function PressConfig.RollItem(rarity: string): { Name: string, Price: number }?
	local items = TreasuresConfig[rarity]
	if not items or #items == 0 then
		return nil
	end
	return items[math.random(1, #items)]
end

return PressConfig
