--[[
	Множитель размера (хитбокс атаки + визуальный Scale оружия) по уровню Range.
	Шаг +1x каждые STEP_LEVELS уровней, максимум MAX_STEPS шагов — дальше уровень
	покупать можно (мнимая прокачка), но размер уже не растёт.
]]

local STEP_LEVELS = 10
local MAX_STEPS = 2 -- максимум x3 (1 база + 2 шага), достигается на 21 уровне

-- X и Z растут ОДНИМ множителем (см. HorizontalMultiplier), чтобы хитбокс
-- оставался квадратным в плане на любом уровне. Сдержаннее полного роста —
-- иначе на максимуме хитбокс становится неадекватно большим. 0.75 = на
-- максимуме x2.5 вместо x3.
local HORIZONTAL_DAMPING = 0.75

local RangeScale = {}

function RangeScale.Multiplier(level: number): number
	-- Уровень < 1 (старые профили со Stats.Range = 0) дал бы множитель 0 -> ScaleTo упадёт.
	local steps = math.clamp(math.floor((level - 1) / STEP_LEVELS), 0, MAX_STEPS)
	return 1 + steps
end

function RangeScale.HorizontalMultiplier(level: number): number
	return 1 + (RangeScale.Multiplier(level) - 1) * HORIZONTAL_DAMPING
end

return RangeScale
