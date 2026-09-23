--[[
	Множитель размера (хитбокс атаки + визуальный Scale оружия) по уровню Range.
	Шаг +1x каждые STEP_LEVELS уровней, максимум MAX_STEPS шагов — дальше уровень
	покупать можно (мнимая прокачка), но размер уже не растёт.
]]

local STEP_LEVELS = 10
local MAX_STEPS = 2 -- максимум x3 (1 база + 2 шага), достигается на 21 уровне

-- Ширина (X, "влево-вправо") растёт медленнее, чем глубина/высота — иначе на
-- максимуме хитбокс становится неадекватно широким. 0.5 = вдвое сдержаннее.
local WIDTH_DAMPING = 0.5

-- Глубина (Z, "вперёд") — чуть сдержаннее полного роста, но всё ещё основной
-- рост от Range. 0.75 = на максимуме x2.5 вместо x3.
local DEPTH_DAMPING = 0.75

local RangeScale = {}

function RangeScale.Multiplier(level: number): number
	-- Уровень < 1 (старые профили со Stats.Range = 0) дал бы множитель 0 -> ScaleTo упадёт.
	local steps = math.clamp(math.floor((level - 1) / STEP_LEVELS), 0, MAX_STEPS)
	return 1 + steps
end

function RangeScale.WidthMultiplier(level: number): number
	return 1 + (RangeScale.Multiplier(level) - 1) * WIDTH_DAMPING
end

function RangeScale.DepthMultiplier(level: number): number
	return 1 + (RangeScale.Multiplier(level) - 1) * DEPTH_DAMPING
end

return RangeScale
