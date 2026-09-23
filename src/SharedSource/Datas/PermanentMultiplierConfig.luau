--[[
	PermanentMultiplierConfig — постоянные (на весь аккаунт, навсегда) множители
	за донат: панель HUD -> BuffBuyButton ("x2 Strength" / "x2 Money").

	В отличие от BuffConfig (временные баффы, складываются друг с другом по
	времени), здесь ступени ПОСЛЕДОВАТЕЛЬНЫЕ и каждая следующая ЗАМЕНЯЕТ
	предыдущую (см. PermanentMultiplierHandler:Grant) — купил x8, x2 и x4 уже
	не нужны, x8 полностью их перекрывает.

	Bonus — на сколько текущая ступень добавляет к итоговому множителю
	(складывается с rebirth-множителем и бонусом временного баффа, см.
	PlayerManagerService:GetPlayerCashMultiplier/GetPlayerStrengthMultiplier):
	x2 -> +1, т.к. итоговый множитель = rebirthMultiplier + tempBuffBonus + Bonus
	(тот же принцип, что у BuffConfig.Bonus).

	Единый источник для сервера (PermanentMultiplierHandler/PurchaseHandler) и
	клиента (BuffBuyButton через Data.permanentMultipliers).
]]

export type Tier = {
	Multiplier: number, -- x2, x4, x8...
	Bonus: number, -- Multiplier - 1
	Price: number, -- Robux — только для подписи на кнопке
	ProductId: number,
}

local PermanentMultiplierConfig = {}

PermanentMultiplierConfig.Tiers = {
	Strength = {
		{ Multiplier = 2, Bonus = 1, Price = 2, ProductId = 3713994531 },
		{ Multiplier = 4, Bonus = 3, Price = 8, ProductId = 3713994566 },
		{ Multiplier = 8, Bonus = 7, Price = 29, ProductId = 3713994603 },
		{ Multiplier = 16, Bonus = 15, Price = 59, ProductId = 3713994614 },
		{ Multiplier = 32, Bonus = 31, Price = 139, ProductId = 3713994644 },
		{ Multiplier = 64, Bonus = 63, Price = 299, ProductId = 3713994681 },
	},
	Money = {
		{ Multiplier = 2, Bonus = 1, Price = 89, ProductId = 3713994738 },
		{ Multiplier = 4, Bonus = 3, Price = 249, ProductId = 3713994754 },
		{ Multiplier = 8, Bonus = 7, Price = 599, ProductId = 3713994785 },
		{ Multiplier = 16, Bonus = 15, Price = 1299, ProductId = 3713994815 },
		{ Multiplier = 32, Bonus = 31, Price = 2799, ProductId = 3713994843 },
	},
} :: { [string]: { Tier } }

-- productId -> (buffType, tier, index) для роутинга чеков покупки.
function PermanentMultiplierConfig.ByProductId(productId: number): (string?, Tier?, number?)
	for buffType, tiers in pairs(PermanentMultiplierConfig.Tiers) do
		for index, tier in ipairs(tiers) do
			if tier.ProductId == productId then
				return buffType, tier, index
			end
		end
	end
	return nil, nil, nil
end

-- Следующая непройденная ступень для уже купленного множителя (0 = ещё ничего
-- не куплено). nil, если все ступени уже куплены — кнопку нужно скрыть.
function PermanentMultiplierConfig.NextTier(buffType: string, ownedMultiplier: number): Tier?
	local tiers = PermanentMultiplierConfig.Tiers[buffType]
	if not tiers then
		return nil
	end
	for _, tier in ipairs(tiers) do
		if tier.Multiplier > ownedMultiplier then
			return tier
		end
	end
	return nil
end

return PermanentMultiplierConfig
