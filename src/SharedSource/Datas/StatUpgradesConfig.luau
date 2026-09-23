--[[
	StatUpgradesConfig — конфиг панели Upgrades (прокачка статов за деньги / донат).
	Единый источник для сервера (StatUpgradeHandler) и клиента (UpgradesPanel).

	Стат = уровень в профиле Stats.<key> (Range / Agility / Capacity / Mobility),
	его читает PlayerStatsInitializer через атрибут "<key>Level" и пересчитывает
	реальные значения в PlayerStatsContainer.

	Бонус (`Bonus`) — СТАТИЧНЫЙ текст «за уровень», только для отображения; на
	реальную формулу стата не влияет (она в PlayerStatsContainer).

	Цена следующего уровня растёт тирами по TIER_SIZE уровней: внутри тира —
	постоянный темп, на границе каждого тира темп сам увеличивается в
	TIER_GROWTH раз (это и даёт периодический "рывок" цены). Единственное,
	что отличает статы друг от друга — BaseCost; форма кривой (темпы, рывки)
	общая для всех статов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)

export type StatConfig = {
	Title: string,
	Bonus: string, -- статичный текст бонуса за 1 уровень, напр. "+10% Atk. Speed"
	Icon: string, -- rbxassetid или "" — иконку вставляет дизайнер позже

	BaseCost: string, -- цена 1-го апгрейда, EtNum-строка
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
		BaseCost = "6000",
		MaxLevel = 500,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Agility = {
		Title = "Agility",
		Bonus = "+10% Atk. Speed",
		Icon = "98428961100824",
		BaseCost = "15000",
		MaxLevel = 500,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Capacity = {
		Title = "Capacity",
		Bonus = "+1 Slot Space",
		Icon = "15507675979",
		BaseCost = "130000",
		MaxLevel = 200,
		RobuxProductId = 0,
		RobuxLevels = 10,
		RobuxPrice = 0,
	},
	Mobility = {
		Title = "Mobility",
		Bonus = "+1 Move Speed",
		Icon = "107940225956071",
		BaseCost = "10000",
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

-- Цена перехода `level` -> `level + 1`, EtNum-строка. level >= 1.
function StatUpgradesConfig.CostFor(statKey: string, level: number): string
	local cfg = StatUpgradesConfig.Stats[statKey]
	assert(cfg, `StatUpgradesConfig: нет стата "{statKey}"`)

	local base = EtNum.convert(cfg.BaseCost)
	local tier = math.floor((math.max(level, 1) - 1) / TIER_SIZE) -- 0 для 1-10, 1 для 11-20, ...

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
