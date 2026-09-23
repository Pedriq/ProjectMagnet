--[[
	PowerPackConfig — разовая покупка силы за донат (HUD -> PowerBuyButton,
	3 пака: V1/V2/V3). Цена дев-продукта ФИКСИРОВАНА (19/79/249 Robux) — не
	меняется никогда. Меняется только StrengthGrant (сколько силы начисляется
	за покупку) — когда текущие значения устареют по мере роста игры, просто
	поправь их здесь, Label и клиентская кнопка обновятся вместе с ними
	(единый источник, см. HUD.luau).

	Пак можно покупать сколько угодно раз (обычный дев-продукт, без владения/
	ступеней) — в отличие от PermanentMultiplierConfig, тут НЕТ прогрессии
	"следующая ступень заменяет предыдущую".

	ВАЖНО: начисление — БЕЗ множителей (rebirth / временный бафф / постоянный
	донат-множитель), ровно StrengthGrant как есть, см. PowerPackPurchaseHandler.
]]

export type Pack = {
	Label: string, -- подпись на кнопке, напр. "+100k"
	StrengthGrant: string, -- EtNum-строка, сколько силы начисляется (без множителей)
	Price: number, -- Robux — только для подписи, цена дев-продукта не меняется
	ProductId: number,
}

local PowerPackConfig = {}

PowerPackConfig.Packs = {
	{ Label = "+100k", StrengthGrant = "100000", Price = 19, ProductId = 3714001847 }, -- V1
	{ Label = "+5M", StrengthGrant = "5000000", Price = 79, ProductId = 3714001872 }, -- V2
	{ Label = "+100M", StrengthGrant = "100000000", Price = 249, ProductId = 3714001886 }, -- V3
} :: { Pack }

function PowerPackConfig.ByProductId(productId: number): Pack?
	for _, pack in ipairs(PowerPackConfig.Packs) do
		if pack.ProductId == productId then
			return pack
		end
	end
	return nil
end

return PowerPackConfig
