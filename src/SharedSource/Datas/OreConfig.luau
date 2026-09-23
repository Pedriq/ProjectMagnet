-- Руды, которые игрок добывает из камней. Пока руда = камень секции: секция "Common" → руда
-- "CommonRock" (так же называются папки с кусочками в ReplicatedStorage.Assets.Ores).
-- TODO: заменить на настоящие руды (Copper, Iron, ...) и нормальный конфиг весов.
local OreConfig = {}

-- Сколько сегментов (кусочков) у модели камня — части с именами "1".."8"
-- (см. RockVisualizer:UpdateRockDamage).
OreConfig.SEGMENTS_PER_ROCK = 8

-- ЗАГЛУШКА: вес одного кусочка любой руды.
OreConfig.DEFAULT_PIECE_WEIGHT = 10

-- [oreName] = { PieceWeight = number }. Пусто — у всех DEFAULT_PIECE_WEIGHT.
OreConfig.Ores = {}

function OreConfig.GetOreNameForSection(section): string
	return tostring(section) .. "Rock"
end

function OreConfig.GetPieceWeight(oreName: string): number
	local ore = OreConfig.Ores[oreName]
	return ore and ore.PieceWeight or OreConfig.DEFAULT_PIECE_WEIGHT
end

-- Сколько сегментов уже отколото при таком hp. Одна формула для визуала на
-- клиенте и для начисления кусочков на сервере — чтобы числа совпадали.
function OreConfig.GetBrokenSegments(hp: number, maxHp: number): number
	local hpPercent = math.clamp(hp / maxHp, 0, 1)
	return OreConfig.SEGMENTS_PER_ROCK - math.ceil(OreConfig.SEGMENTS_PER_ROCK * hpPercent)
end

return OreConfig
