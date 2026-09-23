--[[
	BuffConfig — временные баффы за донат (панель Shop -> Boosts).
	Единый источник для сервера (BuffPurchaseHandler/BuffHandler) и клиента
	(ShopPanel/BoostCard, ActiveBuffsBar).

	Type — какой множитель баффает: "Strength" (сила за клин) или "Money"
	(деньги за продажу). Bonus — НА СКОЛЬКО добавляется к множителю на время
	баффа (складывается с множителем за ребёрс, см. RebirthConfig): x2 -> +1,
	т.к. итоговый множитель = rebirthMultiplier + Bonus.
]]

export type BuffEntry = {
	Type: "Strength" | "Money",
	Title: string,
	Minutes: number,
	Bonus: number,
	Price: number, -- Robux — только для подписи на кнопке
	ProductId: number,
	Icon: string,
}

local BuffConfig = {}

BuffConfig.Boosts = {
	{ Type = "Strength", Title = "2x Strength", Minutes = 10, Bonus = 1, Price = 9, ProductId = 3713418230, Icon = "96772289336842" },
	{ Type = "Strength", Title = "2x Strength", Minutes = 30, Bonus = 1, Price = 24, ProductId = 3713418270, Icon = "96772289336842" },
	{ Type = "Money", Title = "2x Money", Minutes = 10, Bonus = 1, Price = 39, ProductId = 3713418304, Icon = "117287387544386" },
} :: { BuffEntry }

-- Одна карточка на Type — для отображения в ActiveBuffsBar (иконка одна и та же
-- для всех длительностей одного типа, берём первую попавшуюся).
BuffConfig.Display = {}
for _, entry in ipairs(BuffConfig.Boosts) do
	if not BuffConfig.Display[entry.Type] then
		BuffConfig.Display[entry.Type] = { Icon = entry.Icon }
	end
end

function BuffConfig.ByProductId(productId: number): BuffEntry?
	for _, entry in ipairs(BuffConfig.Boosts) do
		if entry.ProductId == productId then
			return entry
		end
	end
	return nil
end

return BuffConfig
