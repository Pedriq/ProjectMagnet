--[[
	SellBoostConfig — донат-продукт "Sell x2" (панель Sell Loot). Покупка сразу
	продаёт ВЕСЬ текущий инвентарь лута с доп. x2 к цене (поверх обычного
	cashMultiplier — rebirth + временный бафф + постоянный донат-множитель).
	Не ступенчатый и не постоянный — можно покупать повторно каждый раз, когда
	хочется продать лут с бустом.
]]

local SellBoostConfig = {
	ProductId = 3714014901,
	Multiplier = 2, -- x2, поверх обычного PlayerManagerService:GetPlayerCashMultiplier
}

return SellBoostConfig
