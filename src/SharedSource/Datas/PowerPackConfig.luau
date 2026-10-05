--[[
	PowerPackConfig — разовая покупка силы за донат (HUD -> PowerBuyButton,
	3 пака: V1/V2/V3). Цена дев-продукта ФИКСИРОВАНА (19/79/249 Robux) — не
	меняется никогда. Сколько силы даёт пак, зависит от МИРА игрока (Stats.World —
	самый дальний открытый мир, по умолчанию 1): MagnetismGrant — значение для мира 1,
	дальше оно умножается на 10^(WORLD_SCALE_EXPONENT * (мир - 1)), пропорция паков
	(1 : 50 : 1000) сохраняется. Сервер (PowerPackPurchaseHandler) и подпись на кнопке
	(HUD) считают сумму одними и теми же GrantFor / LabelFor.

	Пак можно покупать сколько угодно раз (обычный дев-продукт, без владения/
	ступеней) — в отличие от PermanentMultiplierConfig, тут НЕТ прогрессии
	"следующая ступень заменяет предыдущую".

	ВАЖНО: начисление — БЕЗ множителей (rebirth / временный бафф / постоянный
	донат-множитель), ровно GrantFor(пак, мир) как есть, см. PowerPackPurchaseHandler.
]]

export type Pack = {
	MagnetismGrant: string, -- EtNum-строка, сколько силы начисляется в МИРЕ 1 (без множителей)
	Price: number, -- Robux — только для подписи, цена дев-продукта не меняется
	ProductId: number,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local PowerPackConfig = {}

-- Во сколько раз (в степенях десятки) растут все паки с каждым новым миром:
-- мир 2 = x10^4, мир 3 = x10^8 и т.д. Подбирается под рост силы между мирами —
-- крутить здесь.
PowerPackConfig.WORLD_SCALE_EXPONENT = 4

PowerPackConfig.Packs = {
	{ MagnetismGrant = "100000", Price = 19, ProductId = 3716685524 }, -- V1
	{ MagnetismGrant = "5000000", Price = 79, ProductId = 3716685616 }, -- V2
	{ MagnetismGrant = "100000000", Price = 249, ProductId = 3716685686 }, -- V3
} :: { Pack }

-- Сколько силы даёт пак в мире `world` (>= 1), EtNum-строка.
function PowerPackConfig.GrantFor(pack: Pack, world: number?): string
	local steps = math.max(math.floor(tonumber(world) or 1), 1) - 1
	if steps == 0 then
		return pack.MagnetismGrant
	end
	local scale = EtNum.pow(10, PowerPackConfig.WORLD_SCALE_EXPONENT * steps)
	return EtNum.toString(EtNum.mul(EtNum.convert(pack.MagnetismGrant), scale))
end

-- Подпись на кнопке, напр. "+100K" — ровно та сумма, что начислит GrantFor.
function PowerPackConfig.LabelFor(pack: Pack, world: number?): string
	return "+" .. Format.short(PowerPackConfig.GrantFor(pack, world))
end

function PowerPackConfig.ByProductId(productId: number): Pack?
	for _, pack in ipairs(PowerPackConfig.Packs) do
		if pack.ProductId == productId then
			return pack
		end
	end
	return nil
end

return PowerPackConfig
