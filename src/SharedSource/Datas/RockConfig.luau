--[[
	RockConfig — HP камня по редкости.

	Экспоненциальная кривая: HP(rarity) = round(BASE_HP * SCALE * RATIO ^ (index - 1)),
	index — позиция редкости в RarityOrder (Common = 1). Значения приблизительные
	(баланс ещё не финализирован), не завязывайся на конкретные числа.

	BASE_HP = 10 (Common), RATIO ~6.4 даёт Ascendant (index 13) ~50b HP.
	SCALE — общий множитель поверх кривой: когда весь баланс нужно будет поднять
	в разы, крути только его, не трогая RATIO/BASE_HP.
]]

local BASE_HP = 10
local RATIO = 6.4
local SCALE = 1

local RarityOrder = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Secret",
	"Godly",
	"Divine",
	"Celestial",
	"Eternal",
	"Cosmic",
	"Ascendant",
}

local RockConfig = {}

RockConfig.RarityOrder = RarityOrder
RockConfig.BASE_HP = BASE_HP
RockConfig.RATIO = RATIO
RockConfig.SCALE = SCALE

for index, rarity in ipairs(RarityOrder) do
	RockConfig[rarity] = {
		MaxHp = math.floor(BASE_HP * SCALE * RATIO ^ (index - 1) + 0.5),
	}
end

return RockConfig
