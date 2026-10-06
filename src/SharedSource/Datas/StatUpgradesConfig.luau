--[[
	StatUpgradesConfig — конфиг панели Upgrades (прокачка статов за деньги / донат).
	Единый источник для сервера (StatUpgradeHandler) и клиента (UpgradesPanel).

	Стат = уровень в профиле Stats.<key> (Range / Capacity / Mobility),
	его читает PlayerStatsInitializer через атрибут "<key>Level" и пересчитывает
	реальные значения в PlayerStatsContainer.

	Бонус (`Bonus`) — СТАТИЧНЫЙ текст «за уровень», только для отображения; на
	реальную формулу стата не влияет (она в PlayerStatsContainer).

	Цена следующего уровня — одна из двух кривых (поле Curve), обе по тирам из
	TIER_SIZE уровней:
	  "Tiers" (по умолчанию, старая) — внутри тира постоянный темп, на границе
	    каждого тира темп сам увеличивается в TIER_GROWTH раз;
	  "Bumps" — «буграми»: внутри тира цена растёт мягко (x BUMP_GROWTH за уровень),
	    а на каждом новом тире (11-й, 21-й, ... уровень) — скачок на порядок
	    (x BUMP_JUMP), и снова мягко. Используется у Capacity.
	Кроме кривой статы отличаются только BaseCost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)

-- Ступень платной прокачки: действует, пока текущий уровень стата >= FromLevel
-- (до FromLevel следующей ступени). Последняя ступень действует на все уровни выше —
-- цена дальше не растёт.
export type RobuxStep = {
	FromLevel: number, -- с какого текущего уровня стата ступень действует
	ProductId: number, -- дев-продукт ступени
	Price: number, -- Robux — ТОЛЬКО для подписи на кнопке (цена продукта задаётся в Roblox)
	Levels: number, -- сколько уровней даёт одна покупка этой ступени
}

export type StatConfig = {
	Title: string,
	Bonus: string, -- статичный текст бонуса за 1 уровень, напр. "+10% Atk. Speed"
	Icon: string, -- rbxassetid или "" — иконку вставляет дизайнер позже

	BaseCost: string, -- цена 1-го апгрейда, EtNum-строка
	Curve: ("Tiers" | "Bumps")?, -- форма роста цены (см. CostFor); по умолчанию "Tiers"
	MaxLevel: number,

	RobuxProductId: number, -- id дев-продукта для «купить за донат» (0 = не заведён)
	RobuxLevels: number, -- сколько уровней даёт одна покупка за донат
	RobuxPrice: number, -- цена в Robux — ТОЛЬКО для подписи на кнопке (0 = "?")
	-- Ступенчатая платная прокачка (см. RobuxStepFor). Если задана, RobuxProductId /
	-- RobuxLevels / RobuxPrice выше игнорируются; если нет — они же работают как одна
	-- ступень на все уровни.
	RobuxSteps: { RobuxStep }?,
}

local StatUpgradesConfig = {}

-- порядок карточек в панели
StatUpgradesConfig.Order = { "Range", "Capacity", "Mobility" }

StatUpgradesConfig.Stats = {
	Range = {
		Title = "Range",
		Bonus = "+7.5% Atk. Radius",
		Icon = "140721207149628",
		BaseCost = "9000",
		MaxLevel = 500,
		RobuxProductId = 0, -- не используется: платные ступени — в RobuxSteps
		RobuxLevels = 5,
		RobuxPrice = 0,
		-- 4 ступени по 6 уровней (1-6, 7-12, 13-18, 19+), покупка даёт 5 уровней. Размер
		-- хитбокса растёт до 21-го уровня (RangeScale: 2 шага по 10 уровней), так что путь
		-- 1->6->11->16->21 (24, 24, 48, 96) выбирает весь реальный бонус; с 19-го — 189.
		RobuxSteps = {
			{ FromLevel = 1, ProductId = 3716677165, Price = 24, Levels = 5 }, -- Range 1
			{ FromLevel = 7, ProductId = 3716677189, Price = 48, Levels = 5 }, -- Range 2
			{ FromLevel = 13, ProductId = 3716677208, Price = 96, Levels = 5 }, -- Range 3
			{ FromLevel = 19, ProductId = 3716677224, Price = 189, Levels = 5 }, -- Range 4 и дальше
		},
	},
	Capacity = {
		Title = "Capacity",
		Bonus = "+100 Capacity", -- = BaseStatsValues.CapacityPerLevel
		Icon = "15507675979",
		BaseCost = "150",
		Curve = "Bumps",
		MaxLevel = 200,
		RobuxProductId = 0, -- не используется: платные ступени — в RobuxSteps
		RobuxLevels = 10,
		RobuxPrice = 0,
		-- 4 ступени по 12 уровней (1-12, 13-24, 25-36, 37+), покупка даёт 10 уровней (+1000
		-- вместимости), так что ступень можно купить дважды подряд. Capacity нужна всю игру
		-- (в симуляции баланса ~65 уровней к финалу), поэтому покупка крупнее, чем у Range.
		RobuxSteps = {
			{ FromLevel = 1, ProductId = 3716676962, Price = 24, Levels = 10 }, -- Capacity 1
			{ FromLevel = 13, ProductId = 3716676980, Price = 48, Levels = 10 }, -- Capacity 2
			{ FromLevel = 25, ProductId = 3716676998, Price = 96, Levels = 10 }, -- Capacity 3
			{ FromLevel = 37, ProductId = 3716677024, Price = 189, Levels = 10 }, -- Capacity 4 и дальше
		},
	},
	-- Скорость пресса (profile.Press.CraftSpeed). НЕ в Order — карточка живёт в окне
	-- Press Queue, покупка — PressService:BuySpeedUpgrade. Здесь только цена по
	-- общей формуле CostFor. Реальная скорость — PressConfig.GetCraftItemsPerSecond
	-- (растёт до уровня 50, дальше уровень «фейковый», потолок 5 предметов/сек).
	PressSpeed = {
		Title = "Press Speed",
		Bonus = "+Items per second",
		Icon = "",
		BaseCost = "7500",
		MaxLevel = 500,
		RobuxProductId = 0, -- не используется: платные ступени — в RobuxSteps
		RobuxLevels = 5,
		RobuxPrice = 0,
		-- Платный skip в окне Press Upgrade: те же 4 ступени и цены, что у Range (1-6, 7-12,
		-- 13-18, 19+), покупка даёт 5 уровней CraftSpeed. Выдача — PressService:GrantSpeedLevels.
		RobuxSteps = {
			{ FromLevel = 1, ProductId = 3716851089, Price = 24, Levels = 5 }, -- Press Speed 1
			{ FromLevel = 7, ProductId = 3716851114, Price = 48, Levels = 5 }, -- Press Speed 2
			{ FromLevel = 13, ProductId = 3716851142, Price = 96, Levels = 5 }, -- Press Speed 3
			{ FromLevel = 19, ProductId = 3716851198, Price = 189, Levels = 5 }, -- Press Speed 4 и дальше
		},
	},
	Mobility = {
		Title = "Mobility",
		Bonus = "+1 Move Speed",
		Icon = "107940225956071",
		BaseCost = "15000",
		MaxLevel = 100,
		RobuxProductId = 0, -- не используется: платные ступени — в RobuxSteps
		RobuxLevels = 5,
		RobuxPrice = 0,
		-- 4 ступени, каждая действует 6 уровней (1-6, 7-12, 13-18, 19+), покупка даёт 5 уровней,
		-- так что ступень можно купить дважды подряд. Скорость бега растёт до
		-- 20-го уровня (PlayerStatsContainer: WalkSpeed + min(level, 20)); путь 1->6->11->16->21
		-- (24, 24, 48, 96) выбирает весь реальный бонус. С 19-го уровня и дальше — 189.
		RobuxSteps = {
			{ FromLevel = 1, ProductId = 3716674364, Price = 24, Levels = 5 }, -- Mobility 1
			{ FromLevel = 7, ProductId = 3716674334, Price = 48, Levels = 5 }, -- Mobility 2
			{ FromLevel = 13, ProductId = 3716674319, Price = 96, Levels = 5 }, -- Mobility 3
			{ FromLevel = 19, ProductId = 3716674287, Price = 189, Levels = 5 }, -- Mobility 4 и дальше
		},
	},
} :: { [string]: StatConfig }

-- Ступени платной прокачки стата (RobuxSteps, а если их нет — одна ступень из
-- RobuxProductId / RobuxLevels / RobuxPrice). Пусто, если продукт не заведён.
function StatUpgradesConfig.RobuxSteps(statKey: string): { RobuxStep }
	local cfg = StatUpgradesConfig.Stats[statKey]
	if not cfg then
		return {}
	end
	if cfg.RobuxSteps then
		return cfg.RobuxSteps
	end
	if cfg.RobuxProductId ~= 0 then
		return {
			{ FromLevel = 1, ProductId = cfg.RobuxProductId, Price = cfg.RobuxPrice, Levels = cfg.RobuxLevels },
		}
	end
	return {}
end

-- Ступень, которая действует при текущем уровне стата `level` (последняя с
-- FromLevel <= level; выше последней — она же). nil — платной прокачки нет.
function StatUpgradesConfig.RobuxStepFor(statKey: string, level: number): RobuxStep?
	local current: RobuxStep? = nil
	for _, step in ipairs(StatUpgradesConfig.RobuxSteps(statKey)) do
		if step.FromLevel <= level then
			current = step
		end
	end
	return current or StatUpgradesConfig.RobuxSteps(statKey)[1]
end

-- через сколько уровней происходит рывок цены, и насколько сильно
local TIER_SIZE = 10
local RATE_START = 1.75 -- темп роста за уровень внутри первого десятка
local TIER_GROWTH = 1.5 -- во сколько раз сам темп усиливается с каждым следующим десятком

-- кривая "Bumps"
local BUMP_GROWTH = 1.15 -- +15% за уровень внутри тира
local BUMP_JUMP = 10 -- скачок цены при переходе в следующий тир

-- Цена перехода `level` -> `level + 1`, EtNum-строка. level >= 1.
function StatUpgradesConfig.CostFor(statKey: string, level: number): string
	local cfg = StatUpgradesConfig.Stats[statKey]
	assert(cfg, `StatUpgradesConfig: нет стата "{statKey}"`)

	local base = EtNum.convert(cfg.BaseCost)
	local tier = math.floor((math.max(level, 1) - 1) / TIER_SIZE) -- 0 для 1-10, 1 для 11-20, ...

	if cfg.Curve == "Bumps" then
		-- base * 1.15^(level-1) * 10^tier
		local cost = EtNum.mul(base, EtNum.pow(BUMP_GROWTH, math.max(level, 1) - 1))
		return EtNum.toString(EtNum.mul(cost, EtNum.pow(BUMP_JUMP, tier)))
	end

	if tier == 0 then
		return EtNum.toString(EtNum.mul(base, EtNum.pow(RATE_START, level - 1)))
	end

	local boundaryCost = EtNum.mul(base, EtNum.pow(RATE_START, TIER_SIZE - 1)) -- cost(10)
	local rate = RATE_START

	for _ = 1, tier - 1 do
		rate *= TIER_GROWTH
		boundaryCost = EtNum.mul(boundaryCost, EtNum.pow(rate, TIER_SIZE))
	end
	rate *= TIER_GROWTH

	return EtNum.toString(EtNum.mul(boundaryCost, EtNum.pow(rate, level - tier * TIER_SIZE)))
end

return StatUpgradesConfig
