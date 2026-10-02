--[[
	ComboConfig — комбо и криты ручного клика. Единый источник для сервера
	(ClickHandler — реальное начисление) и клиента (combo.luau — счётчик/превью).

	Комбо: каждый ручной клик не позже WINDOW секунд после предыдущего +1 к
	комбо, пауза дольше — комбо сгорает. Бонус к силе за клик:
	  1 + min(combo, MAX_COMBO) * BONUS_PER_CLICK   (до x2 на 100 комбо).
	Крит: CRIT_CHANCE шанс на ручной клик, сила за этот клик x CRIT_MULTIPLIER.

	Автоудар оружия и автозоны комбо/криты не получают — это награда именно
	за активную игру.
]]

local ComboConfig = {}

ComboConfig.WINDOW = 0.9
ComboConfig.MAX_COMBO = 100
ComboConfig.BONUS_PER_CLICK = 0.01

ComboConfig.CRIT_CHANCE = 0.08
ComboConfig.CRIT_MULTIPLIER = 3

-- Античит: больше стольких ручных кликов в секунду сервер не засчитывает.
ComboConfig.MAX_CLICKS_PER_SECOND = 20

-- Рубежи комбо, на которых клиент празднует (баннер + звук).
ComboConfig.MILESTONES = { 10, 25, 50, 100 }

function ComboConfig.Multiplier(combo: number): number
	return 1 + math.min(math.max(combo, 0), ComboConfig.MAX_COMBO) * ComboConfig.BONUS_PER_CLICK
end

return ComboConfig
