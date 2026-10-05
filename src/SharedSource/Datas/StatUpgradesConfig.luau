--[[
	StatUpgradesConfig — конфиг панели Upgrades (прокачка статов за деньги / донат).
	Единый источник для сервера (StatUpgradeHandler) и клиента (UpgradesPanel).

	Стат = уровень в профиле Stats.<key> (Range / Agility / Capacity / Mobility),
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
}

local StatUpgradesConfig = {}

-- порядок карточек в панели
StatUpgradesConfig.Order = { "Range", "Agility", "Capacity", "Mobility" }

StatUpgradesConfig.Stats = {
	Range = {
		Title = "Range",
		Bonus = "+7.5% Atk. Radius",
		Icon = "140721207149628",
		BaseCost = "9000",
		MaxLevel = 500,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Agility = {
		Title = "Agility",
		Bonus = "+10% Atk. Speed",
		Icon = "98428961100824",
		BaseCost = "22500",
		MaxLevel = 500,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Capacity = {
		Title = "Capacity",
		Bonus = "+100 Capacity", -- = BaseStatsValues.CapacityPerLevel
		Icon = "15507675979",
		BaseCost = "150",
		Curve = "Bumps",
		MaxLevel = 200,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
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
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Mobility = {
		Title = "Mobility",
		Bonus = "+1 Move Speed",
		Icon = "107940225956071",
		BaseCost = "15000",
		MaxLevel = 100,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
} :: { [string]: StatConfig }

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
