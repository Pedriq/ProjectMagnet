--[[
	theme — единая палитра интерфейса: «магнитная машина на свалке металлолома».

	Язык цвета (одинаковый во всём UI — игрок по цвету понимает смысл):
	  Steel*    — поверхности: тёмный графит / оружейный металл (панели, карточки, треки);
	  Electric* — МАГНИТ: сила (Magnetism), магазин магнитов, прокачки, основные действия;
	  Copper*   — МЕТАЛЛОЛОМ И ПРЕСС: руда, инвентарь, очередь пресса, переработка;
	  Money*    — ДЕНЬГИ: суммы, цены за Money, продажа, сбор;
	  Gold*     — ПРЕМИУМ: покупки за Robux, донат-множители;
	  Rebirth*  — ребёрс (фиолетовый, «трансформация»);
	  Danger / Warning — опасность (BAG FULL, удаление) и предупреждение (почти полон).
	Редкости предметов — SharedSource.Datas.RarityColors (самые яркие цвета в UI,
	чтобы ценное сразу выделялось на приглушённом металле).

	Использование: local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
	  Theme.Electric, Theme.Steel800, Theme.panel("Electric") ...
]]

local Theme = {}

---- металл (от самого тёмного к светлому)
Theme.Steel950 = Color3.fromRGB(10, 12, 15) -- тени, обводки «в глубину»
Theme.Steel900 = Color3.fromRGB(15, 17, 21) -- треки полос, утопленные поля
Theme.Steel800 = Color3.fromRGB(22, 25, 31) -- тело панелей (основной фон)
Theme.Steel700 = Color3.fromRGB(31, 35, 43) -- карточки/строки на панели
Theme.Steel600 = Color3.fromRGB(44, 50, 61) -- приподнятые элементы, неактивные кнопки
Theme.Steel500 = Color3.fromRGB(68, 77, 92) -- тонкие рамки, разделители
Theme.Steel400 = Color3.fromRGB(104, 115, 132) -- блики на кромках
Theme.Steel300 = Color3.fromRGB(150, 160, 176) -- второстепенный текст

---- текст
Theme.Text = Color3.fromRGB(232, 236, 242) -- основной
Theme.TextMuted = Theme.Steel300 -- подписи, подсказки
Theme.Outline = Color3.fromRGB(0, 0, 0) -- обводка текста/элементов

---- магнит: электрический синий
Theme.ElectricDeep = Color3.fromRGB(22, 78, 150)
Theme.Electric = Color3.fromRGB(46, 156, 255)
Theme.ElectricBright = Color3.fromRGB(130, 210, 255)

---- металлолом / пресс: ржавчина и медь
Theme.CopperDeep = Color3.fromRGB(112, 52, 22)
Theme.Copper = Color3.fromRGB(206, 104, 44)
Theme.CopperBright = Color3.fromRGB(246, 156, 86)

---- деньги
Theme.MoneyDeep = Color3.fromRGB(28, 112, 52)
Theme.Money = Color3.fromRGB(78, 214, 104)
Theme.MoneyBright = Color3.fromRGB(150, 245, 160)

---- премиум (Robux, донат)
Theme.GoldDeep = Color3.fromRGB(140, 92, 14)
Theme.Gold = Color3.fromRGB(246, 186, 52)
Theme.GoldBright = Color3.fromRGB(255, 226, 130)

---- ребёрс
Theme.RebirthDeep = Color3.fromRGB(70, 40, 130)
Theme.Rebirth = Color3.fromRGB(156, 104, 255)
Theme.RebirthBright = Color3.fromRGB(205, 175, 255)

---- состояния
Theme.Danger = Color3.fromRGB(232, 64, 64)
Theme.DangerDeep = Color3.fromRGB(120, 26, 30)
Theme.Warning = Color3.fromRGB(255, 166, 40)

---- кнопки: тон «крашеного металла» — насыщеннее Deep, но приглушённее чистого
-- акцента (без кислотных зелёных/жёлтых); важные действия различаются по смыслу
Theme.ButtonElectric = Color3.fromRGB(34, 120, 214) -- основное действие / магнит / прокачка
Theme.ButtonCopper = Color3.fromRGB(178, 84, 34) -- пресс / металлолом
Theme.ButtonMoney = Color3.fromRGB(44, 156, 70) -- купить/продать за Money
Theme.ButtonGold = Color3.fromRGB(206, 146, 30) -- Robux / премиум
Theme.ButtonRebirth = Color3.fromRGB(118, 74, 214) -- ребёрс
Theme.ButtonDanger = Color3.fromRGB(184, 46, 46) -- удалить / необратимое
Theme.ButtonSteel = Color3.fromRGB(64, 72, 86) -- второстепенное (Base, Skip, …)

---- навигация: яркий электрический — кнопка явно «живая» (Base и т.п.)
Theme.ButtonNav = Color3.fromRGB(38, 150, 255)

---- Магазин (премиум): чистый насыщенный янтарь на нейтральном холодном графите.
-- Без тёмных «Deep»-тонов — градиенты остаются яркими сверху донизу, без бурого.
Theme.ShopTitle = Color3.fromRGB(255, 168, 0) -- янтарь, не коричневый
Theme.ShopBody = Color3.fromRGB(19, 23, 32) -- холодный графит без тёплого оттенка
Theme.ShopBuy = Color3.fromRGB(255, 176, 20) -- кнопка покупки за Robux
Theme.ShopMoneyTop = Color3.fromRGB(140, 255, 160)
Theme.ShopMoneyBottom = Color3.fromRGB(26, 190, 84)
Theme.ShopPowerTop = Color3.fromRGB(140, 220, 255)
Theme.ShopPowerBottom = Color3.fromRGB(22, 128, 245)
Theme.ShopGoldTop = Color3.fromRGB(255, 236, 120)
Theme.ShopGoldBottom = Color3.fromRGB(255, 160, 0)
Theme.ShopRedTop = Color3.fromRGB(255, 120, 120)
Theme.ShopRedBottom = Color3.fromRGB(222, 30, 52)

---- полоса уровня: синий (магнит) -> фиолетовый -> красный
-- По кругу оттенков через фиолетовый (а не через зелёный/жёлтый); несколько
-- точек, чтобы середина не «грязнела» (ColorSequence смешивает в RGB).
Theme.LEVEL_HUE_START = 0.6
Theme.LEVEL_HUE_END = 1.0
Theme.LEVEL_GRADIENT = (function()
	local steps = 6
	local keypoints = {}
	for i = 0, steps do
		local t = i / steps
		local hue = (Theme.LEVEL_HUE_START + (Theme.LEVEL_HUE_END - Theme.LEVEL_HUE_START) * t) % 1
		table.insert(keypoints, ColorSequenceKeypoint.new(t, Color3.fromHSV(hue, 0.85, 1)))
	end
	return ColorSequence.new(keypoints)
end)()

---- поверхности панелей (Panel props)
Theme.PanelBodyTransparency = 0.12 -- тёмный полупрозрачный металл
Theme.PanelStrokeThickness = 2.5
Theme.PanelTitleTexture = "rbxassetid://137638295200351"
Theme.PanelTitleTextureTransparency = 0.6 -- как было во всех панелях (0.78 почти не читалась)

-- Акцент заголовка панели по смыслу окна: "Electric" | "Copper" | "Money" | "Gold" | "Rebirth".
-- Тёмный тон (Deep), чтобы заголовок был «окрашенной сталью», а не кислотным пятном.
function Theme.titleColor(accent: string): Color3
	return (Theme :: any)[accent .. "Deep"] or Theme.Steel600
end

-- Тело панели — графит с еле заметным оттенком акцента (окна различимы, но из одного металла).
function Theme.bodyColor(accent: string): Color3
	local tint = (Theme :: any)[accent] or Theme.Steel500
	return Theme.Steel800:Lerp(tint, 0.06)
end

-- Общие props оформления для components/Panel по акценту окна.
function Theme.panel(accent: string): { [string]: any }
	return {
		TitleColor = Theme.titleColor(accent),
		TitleTextColor = Theme.Text,
		BodyColor = Theme.bodyColor(accent),
		BodyTransparency = Theme.PanelBodyTransparency,
		StrokeColor = Theme.Outline,
		StrokeThickness = Theme.PanelStrokeThickness,
		TitleImage = Theme.PanelTitleTexture,
		TitleImageTransparency = Theme.PanelTitleTextureTransparency,
	}
end

-- Вертикальный градиент «полированный металл» для кнопок/полос: светлее сверху.
function Theme.sheen(color: Color3): ColorSequence
	return ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.22), color:Lerp(Color3.new(0, 0, 0), 0.18))
end

return Theme
