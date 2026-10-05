-- Уровень, необходимый для реберса №n (n = ужé пройденные реберсы + 1):
-- level(n) = LEVEL_PER_REBIRTH * n. Линейный рост: первый реберс — 25 уровень,
-- каждый следующий — на LEVEL_PER_REBIRTH дороже (2-й — 50, 3-й — 75, ...).
local LEVEL_PER_REBIRTH = 25

local RebirthConfig = {
	CashMultiplierPerRebirth = 0.2,
	MagnetismMultiplierPerRebirth = 0.5,
}

-- === Платный Skip Rebirth: ребёрс за Robux без требования по уровню.
-- 4 ступени: ступень выбирается по числу УЖЕ пройденных реберсов (FromRebirths —
-- с какого числа реберсов она действует, до FromRebirths следующей). Последняя
-- ступень действует на все реберсы выше — цена дальше не растёт. Price — ТОЛЬКО
-- подпись на кнопке (цена дев-продукта задаётся в Roblox). Без Skip нужный уровень
-- растёт на 25 за реберс (RequiredLevelForRebirth); ступени идут через 5 реберсов,
-- последняя (самая дорогая) начинается с 15 реберсов и действует дальше.
export type SkipStep = {
	FromRebirths: number,
	ProductId: number,
	Price: number,
}

RebirthConfig.SkipSteps = {
	{ FromRebirths = 0, ProductId = 3716680098, Price = 39 }, -- Skip Rebirth 1: от 0 реберсов
	{ FromRebirths = 5, ProductId = 3716680134, Price = 79 }, -- Skip Rebirth 2: от 5 реберсов
	{ FromRebirths = 10, ProductId = 3716680187, Price = 129 }, -- Skip Rebirth 3: от 10 реберсов
	{ FromRebirths = 15, ProductId = 3716680255, Price = 179 }, -- Skip Rebirth 4: от 15 реберсов и дальше
} :: { SkipStep }

-- Ступень Skip для игрока, у которого пройдено `rebirths` реберсов.
function RebirthConfig.SkipStepFor(rebirths: number): SkipStep
	local current = RebirthConfig.SkipSteps[1]
	for _, step in ipairs(RebirthConfig.SkipSteps) do
		if step.FromRebirths <= rebirths then
			current = step
		end
	end
	return current
end

-- rebirths — сколько реберсов уже пройдено. Возвращает требуемый уровень для следующего.
function RebirthConfig.RequiredLevelForRebirth(rebirths: number): number
	return LEVEL_PER_REBIRTH * (rebirths + 1)
end

return RebirthConfig
