local ProfileTemplate = {
	-- Обработанные чеки донат-продуктов: map[PurchaseId] = os.time() (MarketplaceReceiptRouter) —
	-- повторная доставка чека (падение сервера до сохранения) не выдаёт покупку второй раз.
	Receipts = {},

	Magnet = {
		Name = "FridgeMagnet",
		Magnetism = 1,
	},

	-- какими мечами игрок владеет: map[magnetName] = true (см. MagnetData / MagnetShopHandler).
	-- стартовый FridgeMagnet доступен всегда.
	OwnedMagnets = {
		FridgeMagnet = true,
	},

	Stats = {
		Range = 1,
		Capacity = 1,
		Mobility = 1,

		Level = 1,
		Magnetism = "0",
		Rebirth = 0,
		World = 1, -- самый дальний открытый мир (от него зависит размер Magnetism-паков, см. PowerPackConfig)

		Money = "140",
	},

	Items = {},

	-- Купленные донатные автоклик-зоны: map[ZoneId] = true. Копия владения Game Pass'ом,
	-- пишется при подтверждённой покупке (AutoClickZonePlayerData) — чтобы покупка
	-- переживала перезапуск и в тест-режиме Studio, где Roblox владение не отдаёт.
	AutoClickZones = {},

	-- Сохранённая руда: map[oreId] = суммарный вес (oreId — Id из OreConfig).
	-- Пополняется на базе из инвентаря переноски, см. PlayerOreInventory.
	Ores = {},

	-- Гидравлический пресс (см. PressService / PressConfig):
	--   Ores — руда, выгруженная в пресс и ещё не переплавленная: map[oreId] = вес;
	--   UnloadSpeed / CraftSpeed — уровни характеристик пресса (прокачка — позже);
	--   Unclaimed — деньги за проданные прессом предметы (EtNum-строка), ждут,
	--   пока игрок наступит на HydraulicPress.Collect (см. PressCollectHandler).
	Press = {
		Ores = {},
		Unclaimed = "0",
		UnloadSpeed = 1,
		CraftSpeed = 1,
		-- Ore Merge (PressMergeConfig): MergeLevel — прокачка «Merge Efficiency» (ratio 3:1 -> 2:1);
		-- HighestOre — индекс (OreConfig.Order) высшего достигнутого тира руды, выше него merge не поднимает.
		MergeLevel = 1,
		HighestOre = 1,
	},

	-- Обучение новых игроков (клиент: UI/tutorial). Completed = true — пройдено (или игрок
	-- уже опытный), больше не запускается; сам прогресс по шагам выводится из состояния игры.
	Tutorial = {
		Completed = false,
	},

	-- Настройки игрока (окно Settings): громкость музыки и звуков, 0..1 (1 = базовая громкость игры).
	-- Пишется сервером по PlayerManagerService:SetAudioSetting, читается клиентом из снапшота профиля.
	Settings = {
		MusicVolume = 1,
		SfxVolume = 1,
	},

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
	-- Game Pass «OP Auto Collect» куплен (AutoCollectPassHandler): деньги пресса зачисляются
	-- автоматически (PressCollectHandler), кнопка в HUD скрыта навсегда.
	AutoCollectPass = false,

	PermanentMultipliers = {
		Magnetism = 0,
		Money = 0,
	},
}

return ProfileTemplate
