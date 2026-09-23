--[[
	RarityColors — цвет редкости предмета для UI (названия в Sell Loot, попапы и т.п.).
	Ключи совпадают с редкостями из TreasuresConfig.
]]

local DEFAULT = Color3.fromRGB(236, 240, 236)

local RarityColors = {
	Common = Color3.fromRGB(236, 240, 236),
	Uncommon = Color3.fromRGB(120, 235, 130),
	Rare = Color3.fromRGB(90, 172, 255),
	Epic = Color3.fromRGB(190, 120, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
	Mythic = Color3.fromRGB(255, 110, 90),
	Secret = Color3.fromRGB(255, 92, 200),
	Godly = Color3.fromRGB(255, 240, 150),
	Divine = Color3.fromRGB(140, 255, 236),
	Celestial = Color3.fromRGB(170, 200, 255),
	Eternal = Color3.fromRGB(255, 162, 100),
	Cosmic = Color3.fromRGB(150, 120, 255),
	Ascendant = Color3.fromRGB(255, 255, 255),
}

function RarityColors.get(rarity: string?): Color3
	return (rarity and RarityColors[rarity]) or DEFAULT
end

return RarityColors
