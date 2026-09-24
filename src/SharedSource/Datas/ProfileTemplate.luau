local ProfileTemplate = {
	Magnet = {
		Name = "Stick",
		Magnetism = 1,
	},

	-- какими мечами игрок владеет: map[magnetName] = true (см. MagnetData / MagnetShopHandler).
	-- стартовый Stick доступен всегда.
	OwnedMagnets = {
		Stick = true,
	},

	Stats = {
		Range = 1,
		Agility = 1,
		Capacity = 1,
		Mobility = 1,

		Level = 1,
		Magnetism = "0",
		Rebirth = 0,

		Money = "140",
	},

	Items = {},

	-- Сохранённая руда: map[oreId] = суммарный вес (oreId — Id из OreConfig).
	-- Пополняется на базе из инвентаря переноски, см. PlayerOreInventory.
	Ores = {},

	-- Имена предметов, заблокированные от продажи (панель Sell Loot, кнопка
	-- Lock): map[itemName] = true. Блокировка — по ИМЕНИ (вся стопка сразу,
	-- как она и группируется в панели), а не по конкретному id — так же
	-- автоматически блокируются и новые предметы этого имени, собранные позже.
	LockedItems = {},

	Multipliers = {
		Cash = "1",
		Magnetism = "1",
	},

	-- Активные временные баффы (панель Shop -> Boosts): map[buffType] = { ExpiresAt, Bonus }.
	-- ExpiresAt — os.time() (реальные часы, переживает рестарт сервера/релог),
	-- см. BuffHandler.
	Buffs = {},

	-- Постоянные множители за донат (HUD -> BuffBuyButton): 0 = ещё не куплен,
	-- иначе — текущий купленный множитель (2/4/8/...). Каждая следующая ступень
	-- ЗАМЕНЯЕТ предыдущую, см. PermanentMultiplierConfig/PermanentMultiplierHandler.
	-- Ключи те же, что у BuffConfig.Type/BuffHandler ("Magnetism"/"Money") — НЕ
	-- "Cash" (так исторически называется только базовый множитель за ребёрс,
	-- см. Multipliers.Cash выше).
	PermanentMultipliers = {
		Magnetism = 0,
		Money = 0,
	},
}

return ProfileTemplate
