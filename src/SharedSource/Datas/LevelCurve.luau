-- Кривая опыта/уровней. Единый источник для сервера (ClickHandler) и клиента (HUD).
-- Опыт = сила (Magnetism).

local BASE_XP = 45
local MULTIPLIER = 1.09176

local LevelCurve = {}

LevelCurve.BASE_XP = BASE_XP
LevelCurve.MULTIPLIER = MULTIPLIER

-- Сколько опыта нужно НАБРАТЬ внутри уровня `level`, чтобы получить следующий.
-- XP(L) = round(45 * 1.09176^(L-1))
function LevelCurve.RequiredForLevel(level: number): number
	return math.floor(BASE_XP * (MULTIPLIER ^ (level - 1)) + 0.5)
end

-- Суммарный опыт на входе в уровень `level` (то есть за все предыдущие уровни).
function LevelCurve.TotalForLevel(level: number): number
	local total = 0
	for i = 1, level - 1 do
		total += LevelCurve.RequiredForLevel(i)
	end
	return total
end

return LevelCurve
