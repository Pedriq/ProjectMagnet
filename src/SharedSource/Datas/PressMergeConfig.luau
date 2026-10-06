local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)

--[[
	PressMergeConfig — Ore Merge: ручное объединение руды в Press Queue.

	Правила:
	  * Объединяется только руда ОДНОГО типа: `ratio` предметов-эквивалентов руды тира k
	    -> 1 предмет-эквивалент тира k+1. Единица — «предмет» = OreConfig.WeightPerItem
	    (то, что и показывает Press Queue: «x3»). Руда хранится весом, поэтому и
	    дробный остаток, и дробный ratio (2.9:1) работают без особых случаев.
	  * Берётся максимум полных групп: 7 предметов Uncommon при 3:1 -> 2 Rare + 1 Uncommon.
	  * Выше самого высокого достигнутого тира (HighestIndex) не поднимается никогда.
	  * Только по нажатию игрока (кнопка Merge в строке руды / Merge All) — не авто.

	Баланс (почему это чистка мусора, а не бесплатная руда):
	  Вес предмета растёт от тира к тиру всего в ~1.3-1.6 раза (OreConfig: 50, 60, 96,
	  120, ...), а merge тратит `ratio` >= 2 предметов. То есть тир k+1 через merge
	  обходится в ~1.5-2.4 раза БОЛЬШЕ веса руды, чем добыча руды k+1 напрямую, а вес —
	  главный лимит игрока (вместимость сумки). Merge строго невыгоден как способ
	  добычи и годится только чтобы пристроить уже лежащий в очереди мусор. Поэтому
	  ratio никогда не опускается ниже MIN_RATIO = 2 (1:1 был бы выгодным) — это
	  инвариант, который обеспечивает GetRatio.

	Прокачка «Merge Efficiency» (Press Upgrade, за Money): 8 покупок, ratio плавно
	3 -> 2.9 -> ... -> 2:1. Цена — по кривой Press Speed на заданных уровнях
	(StatUpgradesConfig.CostFor("PressSpeed", ...)), т.е. в масштабе остальной
	прогрессии; последняя покупка (2:1) — самая дорогая.
]]

local PressMergeConfig = {}

PressMergeConfig.MIN_RATIO = 2
-- ratio по уровню прокачки (уровень 1 = база 3:1).
PressMergeConfig.Ratios = { 3, 2.9, 2.8, 2.65, 2.5, 2.35, 2.2, 2.1, 2 }
PressMergeConfig.MaxLevel = #PressMergeConfig.Ratios

-- Уровень Press Speed, по чьей цене продаётся улучшение `level -> level + 1`.
local COST_AS_PRESS_SPEED_LEVEL = { 10, 13, 16, 19, 23, 27, 31, 36 }

local EPS = 1e-9

function PressMergeConfig.ClampLevel(level: any): number
	return math.clamp(math.floor(tonumber(level) or 1), 1, PressMergeConfig.MaxLevel)
end

function PressMergeConfig.GetRatio(level: any): number
	return math.max(PressMergeConfig.Ratios[PressMergeConfig.ClampLevel(level)], PressMergeConfig.MIN_RATIO)
end

-- "3:1", "2.9:1"
function PressMergeConfig.RatioText(level: any): string
	return string.format("%g:1", PressMergeConfig.GetRatio(level))
end

-- Цена (EtNum-строка) улучшения `level -> level + 1`; nil на максимальном уровне.
function PressMergeConfig.UpgradeCost(level: any): string?
	local lvl = PressMergeConfig.ClampLevel(level)
	local pressSpeedLevel = COST_AS_PRESS_SPEED_LEVEL[lvl]
	if not pressSpeedLevel then
		return nil
	end
	return StatUpgradesConfig.CostFor("PressSpeed", pressSpeedLevel)
end

-- Индекс (в OreConfig.Order) высшего достигнутого тира: сохранённый рекорд, а также
-- любая руда, лежащая в `ores` (на случай профилей без рекорда).
function PressMergeConfig.HighestIndex(stored: any, ores: { [string]: number }?): number
	local highest = math.max(math.floor(tonumber(stored) or 1), 1)
	if ores then
		for index, oreId in ipairs(OreConfig.Order) do
			if (tonumber(ores[oreId]) or 0) > 0 then
				highest = math.max(highest, index)
			end
		end
	end
	return math.min(highest, #OreConfig.Order)
end

export type Step = { From: string, To: string, Groups: number, Consumed: number, Produced: number }

--[[
	Plan — чистая функция (один и тот же расчёт на сервере и в превью на клиенте).
	  ores         map[oreId] = вес руды в прессе
	  ratio        сколько предметов тира k нужно на 1 предмет тира k+1
	  highestIndex высший достигнутый тир (в OreConfig.Order): выше него руда не создаётся
	  onlyOreId    только эта руда (один шаг, без каскада); nil — все руды снизу вверх
	               (результат нижнего тира сразу идёт в следующий — каскад)
	Возвращает (новые веса — копия `ores`, список шагов).
]]
function PressMergeConfig.Plan(
	ores: { [string]: number },
	ratio: number,
	highestIndex: number,
	onlyOreId: string?
): ({ [string]: number }, { Step })
	ratio = math.max(ratio, PressMergeConfig.MIN_RATIO)
	local result = table.clone(ores)
	local steps: { Step } = {}

	-- шаг k -> k+1 возможен для k < highestIndex (результат <= highestIndex)
	for index = 1, math.min(highestIndex, #OreConfig.Order) - 1 do
		local fromId = OreConfig.Order[index]
		if onlyOreId == nil or onlyOreId == fromId then
			local toId = OreConfig.Order[index + 1]
			local from = OreConfig.Get(fromId)
			local to = OreConfig.Get(toId)
			local weight = tonumber(result[fromId]) or 0
			if from and to and weight > 0 then
				local groups = math.floor(weight / from.WeightPerItem / ratio + EPS)
				if groups > 0 then
					local consumed = math.min(groups * ratio * from.WeightPerItem, weight)
					local produced = groups * to.WeightPerItem
					local left = weight - consumed
					result[fromId] = if left > 1e-6 then left else nil
					result[toId] = (tonumber(result[toId]) or 0) + produced
					table.insert(steps, {
						From = fromId,
						To = toId,
						Groups = groups,
						Consumed = consumed,
						Produced = produced,
					})
				end
			end
		end
	end

	return result, steps
end

return PressMergeConfig
