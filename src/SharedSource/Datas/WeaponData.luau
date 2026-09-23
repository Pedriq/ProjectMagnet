--[[
	WeaponData — конфиг мечей («Cutters»). Единый источник для сервера
	(WeaponShopHandler / PlayerWeaponHitboxManager) и клиента (WeaponShopPanel).

	Плоская карта: ключ = внутреннее имя меча = имя модели в
	ReplicatedStorage.Assets.Weapons = то, что лежит в профиле Weapon.Name.

	Поля меча:
	  Name        — то же, что ключ (для удобства чтения кода)
	  Display     — как показывать в UI (можно с пробелами); по умолч. = Name
	  Rare        — редкость (ключ RarityColors / RarityOrder)
	  Strength    — прирост силы за один клин (число), см. ClickHandler.
	                У Dynamic-мечей отсутствует (сила считается на лету).
	  Price       — цена за Money, EtNum-строка. НЕТ поля => меч не продаётся
	                за Money (стартовый Stick, либо GamePassId-меч). "2.8e8" = 280M и т.п.
	  RobuxPrice  — только для подписи на кнопке Robux (0/nil => "Buy").
	  RobuxProductId — дев-продукт покупки этого меча за Robux (в обход цены
	                Money) — см. WeaponRobuxPurchaseHandler. Не путать с
	                GamePassId: тот — для донат-мечей, которые ВООБЩЕ не
	                продаются за Money (OP Swords).
	  GamePassId  — донат-меч: продаётся ТОЛЬКО за Game Pass (Price не задан).
	                Владение подтверждает сам Roblox, см. WeaponGamePassPurchaseHandler
	                (аналогично AutoClickZone).
	  Dynamic     — { Multiplier } — сила меча не фиксирована: считается как
	                (сила самого сильного НЕ-Dynamic меча, которым владеет игрок) * Multiplier.
	                Пересчитывается заново при каждой экипировке
	                (WeaponShopHandler:EquipWeapon), см. WeaponData.effectiveStrength.
	  Icon        — rbxassetid картинки меча в карточке ("" => пустой квадрат)

	  TextEffect (0..3) / CardEffect (0..4) — переопределяют эффект лейбла редкости
	  и фона карточки. Если не заданы — берутся из RarityEffects по редкости (Mythic+).

	ЭФФЕКТЫ (только Mythic и выше). Значения: см. components/RarityText и
	components/WeaponCard.
	  Текст:  1 — обводка/заливка «меняются местами» по вертикали (перелив)
	          2 — цветной градиент-перелив слева направо
	          3 — радужный перелив слева направо
	  Карта (каждый самостоятельный, не комбинируется):
	          1 — пульс оттенка светлее<->темнее
	          2 — 2 толстые полосы света едут по карточке
	          3 — плавная смена разных цветов
	          4 — плавная смена цветов радуги (как на макете у Mythic)
]]

export type Weapon = {
	Name: string,
	Display: string?,
	Rare: string,
	Strength: number?,
	Price: string?,
	RobuxPrice: number?,
	RobuxProductId: number?,
	GamePassId: number?,
	Dynamic: { Multiplier: number }?,
	Icon: string?,
	TextEffect: number?,
	CardEffect: number?,
}

local Weapons: { [string]: Weapon } = {
	Stick = {
		Name = "Stick",
		Rare = "Common",
		Strength = 1,
	},
	ChippedSword = {
		Name = "Chipped Sword",
		Rare = "Common",
		Strength = 3,
		Price = "150",
		RobuxPrice = 4,
		RobuxProductId = 3714051685,
		Icon = "",
	},
	ChefsFavourite = {
		Name = "Chef's Favourite",
		Rare = "Uncommon",
		Strength = 8,
		Price = "700",
		RobuxPrice = 6,
		RobuxProductId = 3714051763,
		Icon = "",
	},
	LeafyLasher = {
		Name = "Leafy Lasher",
		Rare = "Uncommon",
		Strength = 15,
		Price = "2500",
		RobuxPrice = 9,
		RobuxProductId = 3714051821,
		Icon = "",
	},
	DaybreakDaimyoDaikatana = {
		Name = "Daybreak Daimyo Daikatana",
		Rare = "Uncommon",
		Strength = 25,
		Price = "5000",
		RobuxPrice = 12,
		RobuxProductId = 3714051902,
		Icon = "",
	},
	DuneNomadSword = {
		Name = "Dune Nomad Sword",
		Rare = "Rare",
		Strength = 50,
		Price = "12000",
		RobuxPrice = 16,
		RobuxProductId = 3714051983,
		Icon = "",
	},
	BlossomBarbarianBiter = {
		Name = "Blossom Barbarian Biter",
		Rare = "Rare",
		Strength = 85,
		Price = "30000",
		RobuxPrice = 24,
		RobuxProductId = 3714052066,
		Icon = "",
	},
	StringerBean = {
		Name = "Stringer Bean",
		Rare = "Rare",
		Strength = 170,
		Price = "70000",
		RobuxPrice = 34,
		RobuxProductId = 3714052132,
		Icon = "",
	},
	SnowtrailStalkerSword = {
		Name = "Snowtrail Stalker Sword",
		Rare = "Rare",
		Strength = 360,
		Price = "140000",
		RobuxPrice = 59,
		RobuxProductId = 3714052185,
		Icon = "",
	},
	PanateanBattleAxe = {
		Name = "Panatean Battle-Axe",
		Rare = "Epic",
		Strength = 750,
		Price = "300000",
		RobuxPrice = 79,
		RobuxProductId = 3714052240,
		Icon = "",
	},
	LunewingEdge = {
		Name = "Lunewing Edge",
		Rare = "Epic",
		Strength = 1500,
		Price = "650000",
		RobuxPrice = 119,
		RobuxProductId = 3714052287,
		Icon = "",
	},
	FeatheredFriendFalchion = {
		Name = "Feathered Friend Falchion",
		Rare = "Epic",
		Strength = 3200,
		Price = "1500000",
		RobuxPrice = 159,
		RobuxProductId = 3714052329,
		Icon = "",
	},
	BeachBuriedShovel = {
		Name = "Beach Buried Shovel",
		Rare = "Epic",
		Strength = 6800,
		Price = "4200000",
		RobuxPrice = 219,
		RobuxProductId = 3714052389,
		Icon = "",
	},
	FieryTyrant = {
		Name = "Fiery Tyrant",
		Rare = "Legendary",
		Strength = 14100,
		Price = "12000000",
		RobuxPrice = 299,
		RobuxProductId = 3714052444,
		Icon = "",
	},
	IncandescentMachete = {
		Name = "Incandescent Machete",
		Rare = "Legendary",
		Strength = 29500,
		Price = "25000000",
		RobuxPrice = 399,
		RobuxProductId = 3714052485,
		Icon = "",
	},
	TwistedTraumatizer = {
		Name = "Twisted Traumatizer",
		Rare = "Legendary",
		Strength = 61500,
		Price = "45000000",
		RobuxPrice = 499,
		RobuxProductId = 3714052537,
		Icon = "",
	},
	CrystallineBlade = {
		Name = "Crystalline Blade",
		Rare = "Legendary",
		Strength = 128000,
		Price = "120000000",
		RobuxPrice = 599,
		RobuxProductId = 3714052577,
		Icon = "",
	},
	EldritchExecutor = {
		Name = "Eldritch Executor",
		Rare = "Mythic",
		Strength = 267000,
		Price = "280000000",
		RobuxPrice = 799,
		RobuxProductId = 3714052620,
		Icon = "",
	},
	FaewindWanderer = {
		Name = "Faewind Wanderer",
		Rare = "Mythic",
		Strength = 558000,
		Price = "750000000",
		RobuxPrice = 999,
		RobuxProductId = 3714052672,
		Icon = "",
	},
	FloweryFae = {
		Name = "Flowery Fae",
		Rare = "Mythic",
		Strength = 11000000,
		Price = "22000000000",
		RobuxPrice = 1299,
		RobuxProductId = 3714052717,
		Icon = "",
	},
	MoonstruckBlade = {
		Name = "Moonstruck Blade",
		Rare = "Mythic",
		Strength = 24000000,
		Price = "60000000000",
		RobuxPrice = 1499,
		RobuxProductId = 3714052779,
		Icon = "",
	},

	-- Донат-мечи: НЕ продаются за Money (нет Price) — только за Game Pass.
	-- Сила не фиксирована (нет Strength) — считается динамически от самого
	-- сильного НЕ-донатного меча игрока, см. WeaponData.effectiveStrength.
	Wraithflame = {
		Name = "Wraithflame",
		Rare = "Secret",
		Dynamic = { Multiplier = 2 }, -- +100% силы самого сильного меча
		GamePassId = 1985637086,
		Icon = "",
	},
	WarringWingblade = {
		Name = "Warring Wingblade",
		Rare = "Godly",
		Dynamic = { Multiplier = 4 }, -- +300% силы самого сильного меча
		GamePassId = 1982529455,
		Icon = "",
	},

	-- легаси: старые профили до наполнения конфига хранят Weapon.Name = "Sword".
	-- Не в Order (в магазине не показывается), нужен только чтобы у таких профилей
	-- собирался хитбокс. Новые профили стартуют со Stick (ProfileTemplate).
	-- Sword = {
	-- 	Name = "Sword",
	-- 	Rare = "Common",
	-- 	Strength = 10,
	-- },
	-- Cleaver = {
	-- 	Name = "Cleaver",
	-- 	Rare = "Uncommon",
	-- 	Strength = 45,
	-- 	Price = "900",
	-- 	RobuxPrice = 0,
	-- 	Icon = "",
	-- },
	-- Katana = {
	-- 	Name = "Katana",
	-- 	Rare = "Rare",
	-- 	Strength = 850,
	-- 	Price = "3.5e4",
	-- 	RobuxPrice = 199,
	-- 	Icon = "",
	-- },
	-- Machete = {
	-- 	Name = "Machete",
	-- 	Rare = "Epic",
	-- 	Strength = 12000,
	-- 	Price = "9e5",
	-- 	RobuxPrice = 349,
	-- 	Icon = "",
	-- },
	-- SwordSaw = {
	-- 	Name = "SwordSaw",
	-- 	Display = "Sword Saw",
	-- 	Rare = "Legendary",
	-- 	Strength = 267000,
	-- 	Price = "2.8e8",
	-- 	RobuxPrice = 799,
	-- 	Icon = "",
	-- },
	-- Axe = {
	-- 	Name = "Axe",
	-- 	Rare = "Mythic",
	-- 	Strength = 558000,
	-- 	Price = "4.5e10",
	-- 	RobuxPrice = 999,
	-- 	Icon = "",
	-- },
	-- Saber = {
	-- 	Name = "Saber",
	-- 	Rare = "Mythic",
	-- 	Strength = 1100000,
	-- 	Price = "2.2e12",
	-- 	RobuxPrice = 1299,
	-- 	Icon = "",
	-- },
	-- Reaper = {
	-- 	Name = "Reaper",
	-- 	Rare = "Secret",
	-- 	Strength = 8000000,
	-- 	Price = "1.8e14",
	-- 	RobuxPrice = 1999,
	-- 	Icon = "",
	-- },
	-- Excalibur = {
	-- 	Name = "Excalibur",
	-- 	Rare = "Godly",
	-- 	Strength = 60000000,
	-- 	Price = "1e16",
	-- 	RobuxPrice = 2999,
	-- 	Icon = "",
	-- },
}

-- Плоская карта мечей + мета-поля (Order / RarityEffects / effectsFor) в одном
-- модуле: сервер обращается как WeaponData[weaponName], панель — к мета-полям.
-- Смешанные типы ключей в Luau не выражаются чисто, поэтому мета-часть — через `any`.
local WeaponData = Weapons :: any

-- Порядок карточек в панели (сверху вниз). Первым — стартовый Stick.
WeaponData.Order = {
	"Stick",
	"ChippedSword",
	"ChefsFavourite",
	"LeafyLasher",
	"DaybreakDaimyoDaikatana",
	"DuneNomadSword",
	"BlossomBarbarianBiter",
	"StringerBean",
	"SnowtrailStalkerSword",
	"PanateanBattleAxe",
	"LunewingEdge",
	"FeatheredFriendFalchion",
	"BeachBuriedShovel",
	"FieryTyrant",
	"IncandescentMachete",
	"TwistedTraumatizer",
	"CrystallineBlade",
	"EldritchExecutor",
	"FaewindWanderer",
	"FloweryFae",
	"MoonstruckBlade",
	-- Wraithflame / WarringWingblade НЕ в Order: у них отдельная карточка
	-- (OPSwordCard) в ShopPanel -> "OP Swords", не показываются в панели Cutters.
}

-- Мечи, продающиеся ТОЛЬКО за Game Pass (WeaponGamePassPurchaseHandler) — НЕ в
-- Order, поэтому отдельный список. Не выводить их через pairs(WeaponData)/Order —
-- та же таблица несёт мета-поля (Order/RarityEffects/effectsFor и т.п.).
WeaponData.GamePassWeapons = {
	"Wraithflame",
	"WarringWingblade",
}

-- Эффект по умолчанию для редкости (Mythic и выше). Ниже Mythic — без эффектов.
WeaponData.RarityEffects = {
	Mythic = { Text = 3, Card = 4 }, -- радуга (как на макете)
	Secret = { Text = 2, Card = 3 }, -- смена цветов
	Godly = { Text = 1, Card = 1 }, -- пульс оттенка
	Divine = { Text = 3, Card = 2 }, -- полосы света
	Celestial = { Text = 2, Card = 4 },
	Eternal = { Text = 1, Card = 1 },
	Cosmic = { Text = 3, Card = 4 },
	Ascendant = { Text = 3, Card = 2 },
}

-- { Text = n, Card = n } для меча: приоритет у полей меча, потом RarityEffects.
function WeaponData.effectsFor(weapon: Weapon): { Text: number, Card: number }
	local base = WeaponData.RarityEffects[weapon.Rare] or { Text = 0, Card = 0 }
	return {
		Text = weapon.TextEffect or base.Text,
		Card = weapon.CardEffect or base.Card,
	}
end

-- Восстановить внутренний ключ по любому значению, когда-либо лежавшему в
-- profile.Weapon.Name: сам ключ ("ChefsFavourite"), старое испорченное
-- отображаемое имя ("Chef's Favourite" — баг EquipWeapon до фикса) или мусор.
-- nil, если не нашли ничего похожего.
function WeaponData.resolveKey(nameOrKey: string?): string?
	if type(nameOrKey) ~= "string" then
		return nil
	end

	if Weapons[nameOrKey] then
		return nameOrKey
	end

	for key, weapon in pairs(Weapons) do
		if weapon.Name == nameOrKey then
			return key
		end
	end

	return nil
end

-- Сила самого сильного НЕ-Dynamic меча, которым владеет игрок (owned = OwnedWeapons
-- игрока, map[key]=true). Stick всегда в OwnedWeapons (ProfileTemplate), так что
-- результат никогда не бывает меньше 1 для обычного профиля.
function WeaponData.strongestOwnedStrength(owned: { [string]: boolean }): number
	local best = 0
	for key, weapon in pairs(Weapons) do
		if owned[key] and not weapon.Dynamic and (weapon.Strength or 0) > best then
			best = weapon.Strength
		end
	end
	return best
end

-- Актуальная сила меча `key` для игрока, владеющего `owned`. У Dynamic-мечей
-- (Wraithflame, Warring Wingblade) считается на лету от strongestOwnedStrength,
-- у обычных — просто cfg.Strength.
function WeaponData.effectiveStrength(key: string, owned: { [string]: boolean }): number
	local cfg = Weapons[key]
	if not cfg then
		return 0
	end
	if cfg.Dynamic then
		return WeaponData.strongestOwnedStrength(owned) * cfg.Dynamic.Multiplier
	end
	return cfg.Strength or 0
end

return WeaponData
