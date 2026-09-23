local ProfileTemplate = {
	Weapon = {
		Name = "Stick",
		Strength = 1,
	},

	-- какими мечами игрок владеет: map[weaponName] = true (см. WeaponData / WeaponShopHandler).
	-- стартовый Stick доступен всегда.
	OwnedWeapons = {
		Stick = true,
	},

	Stats = {
		Range = 1,
		Agility = 1,
		Capacity = 1,
		Mobility = 1,

		Level = 1,
		Strength = "0",
		Rebirth = 0,

		Money = "140",
	},

	Items = {},

	-- Имена предметов, заблокированные от продажи (панель Sell Loot, кнопка
	-- Lock): map[itemName] = true. Блокировка — по ИМЕНИ (вся стопка сразу,
	-- как она и группируется в панели), а не по конкретному id — так же
	-- автоматически блокируются и новые предметы этого имени, собранные позже.
	LockedItems = {},

	Multipliers = {
		Cash = "1",
		Strength = "1",
	},

	-- Активные временные баффы (панель Shop -> Boosts): map[buffType] = { ExpiresAt, Bonus }.
	-- ExpiresAt — os.time() (реальные часы, переживает рестарт сервера/релог),
	-- см. BuffHandler.
	Buffs = {},

	-- Постоянные множители за донат (HUD -> BuffBuyButton): 0 = ещё не куплен,
	-- иначе — текущий купленный множитель (2/4/8/...). Каждая следующая ступень
	-- ЗАМЕНЯЕТ предыдущую, см. PermanentMultiplierConfig/PermanentMultiplierHandler.
	-- Ключи те же, что у BuffConfig.Type/BuffHandler ("Strength"/"Money") — НЕ
	-- "Cash" (так исторически называется только базовый множитель за ребёрс,
	-- см. Multipliers.Cash выше).
	PermanentMultipliers = {
		Strength = 0,
		Money = 0,
	},
}

return ProfileTemplate
