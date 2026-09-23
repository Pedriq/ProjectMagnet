-- Уровень, необходимый для реберса №n (n = ужé пройденные реберсы + 1):
-- level(n) = LEVEL_PER_REBIRTH * n. Линейный рост: первый реберс — 25 уровень,
-- каждый следующий — на LEVEL_PER_REBIRTH дороже (2-й — 50, 3-й — 75, ...).
local LEVEL_PER_REBIRTH = 25

local RebirthConfig = {
	CashMultiplierPerRebirth = 0.2,
	MagnetismMultiplierPerRebirth = 0.5,
}

-- rebirths — сколько реберсов уже пройдено. Возвращает требуемый уровень для следующего.
function RebirthConfig.RequiredLevelForRebirth(rebirths: number): number
	return LEVEL_PER_REBIRTH * (rebirths + 1)
end

return RebirthConfig
