--[[
	DamageCurve — урон по камню от накопленной силы (Stats.Magnetism).
	Единый источник для сервера (PlayerMagnetHitboxManager) и клиента
	(OneShotPassThrough): обе стороны обязаны считать урон одинаково.

	HP камней (OreConfig: 10 * 6.4^(зона-1)) и кривая уровней (LevelCurve) рассчитаны
	на то, что урон = вся накопленная сила, а последняя зона берётся примерно к 185
	уровню. Сила теперь копится заметно быстрее (множители, мечи, баффы), поэтому
	«бей всё с одного удара» наступало слишком рано. HP и уровни не трогаем — вместо
	этого урон растёт медленнее силы:

	  total <= SOFT_CAP : урон = total            (зоны 1-3 как раньше — лёгкий старт)
	  total  > SOFT_CAP : урон = SOFT_CAP * (total / SOFT_CAP) ^ EXPONENT

	Кривая непрерывная, без излома в цифрах. Чем больше силы, тем сильнее отставание
	урона: зона 4 берётся на ~+50% силы позже, зона 8 — примерно в 10 раз, последняя
	зона — примерно в 100 раз (~+50 уровней по LevelCurve). Крутить баланс — только
	двумя числами ниже.
]]

local SOFT_CAP = 500 -- до этой силы урон = сила (HP зоны 3 — 410, т.е. зоны 1-3 без изменений)
local EXPONENT = 0.8 -- 1 = без замедления; меньше — урон отстаёт сильнее

local DamageCurve = {}

DamageCurve.SOFT_CAP = SOFT_CAP
DamageCurve.EXPONENT = EXPONENT

-- Урон за удар при накопленной силе `totalMagnetism` (число). Не меньше 1.
function DamageCurve.fromMagnetism(totalMagnetism: number): number
	local damage = totalMagnetism
	if totalMagnetism > SOFT_CAP then
		damage = SOFT_CAP * (totalMagnetism / SOFT_CAP) ^ EXPONENT
	end
	return math.max(1, math.floor(damage + 0.5))
end

return DamageCurve
