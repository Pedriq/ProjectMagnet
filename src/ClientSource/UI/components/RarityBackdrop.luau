local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = vide.create
local clock = rarityFx.clock

--[[
	RarityBackdrop — фон за 3D-превью меча в карточке магазина (MagnetCard -> Icon).
	Каждая редкость — свой «характер», чем выше тир, тем больше слоёв и движения;
	меч остаётся главным (всё живёт ЗА вьюпортом, эффекты мягкие и полупрозрачные).

	Слои (снизу вверх), всё рисуется Frame'ами — без внешних картинок:
	  1. База       — вертикальный градиент тёмного оттенка редкости
	  2. Свечение   — 5 вложенных кругов = мягкое радиальное свечение, «дышит»
	  3. Лучи       — медленно вращающиеся лучи света (Legendary, Mythic)
	  4. Блик       — диагональная полоса света, проезжает раз в несколько секунд
	  5. Пол        — светящийся «эллипс-постамент» под мечом
	  6. Частицы    — поднимающиеся искры/пылинки + мерцающие звёзды
	  7. Виньетка   — затемнение снизу/по краям, чтобы центр читался
	  8. Рамка      — тонкая внутренняя обводка цвета редкости (Rare и выше)

	Common — чистая сталь без анимации; Uncommon — тихое дыхание; Rare — + блик и
	пылинки; Epic — + мерцающие звёзды, пульс быстрее; Legendary — золотые лучи,
	искры, рамка; Mythic — переливающийся цвет, лучи, плотные искры, пульсирующая рамка.

	Использование: RarityBackdrop({ Rarity = "Epic" }) — кладётся первым ребёнком
	контейнера с ClipsDescendants/скруглением; вьюпорту меча дать ZIndex выше.
]]

export type Props = {
	Rarity: string?,
	Radius: UDim?, -- скругление контейнера (по умолч. 5)
}

type Style = {
	Top: Color3,
	Bottom: Color3,
	Glow: Color3, -- цвет свечения/лучей/частиц (если не Cycle)
	GlowStrength: number, -- 0..1.5
	PulseSpeed: number, -- рад/сек «дыхания»
	Motes: number, -- сколько поднимающихся частиц
	MoteSize: number,
	MoteSpeed: number, -- подъёмов в секунду
	Twinkles: number, -- мерцающих звёзд
	RayLines: number, -- лучей-линий (каждая даёт 2 луча); 0 — без лучей
	RaySpeed: number, -- градусов/сек
	Sweep: boolean, -- проезжающий блик
	Floor: number, -- яркость «постамента» 0..1
	Rim: number?, -- прозрачность рамки; nil — без рамки
	Cycle: boolean?, -- цвет свечения переливается (Mythic и выше)
	Hue: { number }?, -- {от, до} диапазон оттенка при Cycle (по умолч. красный..розово-оранжевый)
	Saturation: number?, -- насыщенность переливающегося цвета (по умолч. 0.62)
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STYLES: { [string]: Style } = {
	Common = {
		Top = rgb(78, 86, 99),
		Bottom = rgb(40, 45, 54),
		Glow = rgb(205, 214, 228),
		GlowStrength = 0.28,
		PulseSpeed = 0,
		Motes = 0,
		MoteSize = 2,
		MoteSpeed = 0,
		Twinkles = 0,
		RayLines = 0,
		RaySpeed = 0,
		Sweep = false,
		Floor = 0.18,
	},
	Uncommon = {
		Top = rgb(36, 84, 52),
		Bottom = rgb(14, 36, 24),
		Glow = rgb(110, 235, 130),
		GlowStrength = 0.5,
		PulseSpeed = 1.2,
		Motes = 3,
		MoteSize = 2,
		MoteSpeed = 0.14,
		Twinkles = 0,
		RayLines = 0,
		RaySpeed = 0,
		Sweep = false,
		Floor = 0.3,
	},
	Rare = {
		Top = rgb(26, 62, 122),
		Bottom = rgb(10, 24, 56),
		Glow = rgb(90, 175, 255),
		GlowStrength = 0.68,
		PulseSpeed = 1.5,
		Motes = 4,
		MoteSize = 2.5,
		MoteSpeed = 0.17,
		Twinkles = 0,
		RayLines = 0,
		RaySpeed = 0,
		Sweep = true,
		Floor = 0.45,
		Rim = 0.55,
	},
	Epic = {
		Top = rgb(70, 36, 124),
		Bottom = rgb(26, 12, 56),
		Glow = rgb(196, 124, 255),
		GlowStrength = 0.85,
		PulseSpeed = 1.9,
		Motes = 6,
		MoteSize = 2.5,
		MoteSpeed = 0.2,
		Twinkles = 3,
		RayLines = 0,
		RaySpeed = 0,
		Sweep = true,
		Floor = 0.55,
		Rim = 0.4,
	},
	Legendary = {
		Top = rgb(122, 84, 14),
		Bottom = rgb(50, 30, 6),
		Glow = rgb(255, 204, 70),
		GlowStrength = 1.05,
		PulseSpeed = 2.2,
		Motes = 8,
		MoteSize = 3,
		MoteSpeed = 0.24,
		Twinkles = 3,
		RayLines = 3,
		RaySpeed = 9,
		Sweep = true,
		Floor = 0.65,
		Rim = 0.2,
	},
	-- Secret / Godly — донатные OP-мечи (OPMagnetCard): самый «дорогой» вид
	Secret = {
		Top = rgb(104, 20, 96),
		Bottom = rgb(30, 6, 48),
		Glow = rgb(255, 92, 200),
		GlowStrength = 1.25,
		PulseSpeed = 2.4,
		Motes = 10,
		MoteSize = 3,
		MoteSpeed = 0.28,
		Twinkles = 4,
		RayLines = 4,
		RaySpeed = 12,
		Sweep = true,
		Floor = 0.8,
		Rim = 0.1,
		Cycle = true,
		Hue = { 0.8, 0.93 }, -- фиолетовый <-> маджента
		Saturation = 0.6,
	},
	Godly = {
		Top = rgb(30, 40, 96),
		Bottom = rgb(10, 14, 44),
		Glow = rgb(255, 240, 150),
		GlowStrength = 1.4,
		PulseSpeed = 2.2,
		Motes = 12,
		MoteSize = 3,
		MoteSpeed = 0.26,
		Twinkles = 5,
		RayLines = 5,
		RaySpeed = 8,
		Sweep = true,
		Floor = 0.9,
		Rim = 0.05,
		Cycle = true,
		Hue = { 0.1, 0.16 }, -- тёплое золото <-> светло-жёлтое
		Saturation = 0.5,
	},
	Mythic = {
		Top = rgb(122, 24, 44),
		Bottom = rgb(44, 8, 24),
		Glow = rgb(255, 96, 110),
		GlowStrength = 1.2,
		PulseSpeed = 2.6,
		Motes = 10,
		MoteSize = 3,
		MoteSpeed = 0.3,
		Twinkles = 4,
		RayLines = 4,
		RaySpeed = 16,
		Sweep = true,
		Floor = 0.75,
		Rim = 0.1,
		Cycle = true,
	},
}

-- Повторяемый «случайный» 0..1 по (индекс, соль) — без math.random, чтобы раскладка
-- частиц у карточки не менялась при пересборке.
local function hash(i: number, k: number): number
	return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1
end

local function pulse(speed: number): number
	return 0.5 + 0.5 * math.sin(clock() * speed)
end

local function RarityBackdrop(props: Props)
	local rarity = props.Rarity or "Common"
	local style = STYLES[rarity] or STYLES.Common
	local radius = props.Radius or UDim.new(0, 5)
	local accent = RarityColors.get(rarity)

	-- цвет свечения: у Mythic плавно переливается между красным, оранжевым и маджентой
	local function glowColor(): Color3
		if style.Cycle then
			local range = style.Hue or { 0.99, 1.11 } -- красный..оранжево-розовый (Mythic)
			local hue = range[1] + (range[2] - range[1]) * (0.5 + 0.5 * math.sin(clock() * 0.35))
			return Color3.fromHSV(hue % 1, style.Saturation or 0.62, 1)
		end
		return style.Glow
	end

	--== 2. свечение: 5 вложенных кругов ======================================
	local function glowLayers()
		local layers = {}
		for i = 1, 5 do
			local size = 0.38 + i * 0.15
			layers[i] = create("Frame")({
				Name = `Glow{i}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(size, size),
				BorderSizePixel = 0,
				BackgroundColor3 = glowColor,
				BackgroundTransparency = function()
					local breathe = if style.PulseSpeed > 0 then 0.75 + 0.25 * pulse(style.PulseSpeed) else 1
					local alpha = math.clamp(style.GlowStrength * 0.2 * breathe, 0, 0.9)
					return 1 - alpha
				end,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			})
		end
		return layers
	end

	--== 3. лучи света =========================================================
	local function rays()
		if style.RayLines <= 0 then
			return nil
		end
		local lines = {}
		for i = 1, style.RayLines do
			local baseAngle = (i - 1) * (180 / style.RayLines)
			lines[i] = create("Frame")({
				Name = `Ray{i}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.09, 2),
				BorderSizePixel = 0,
				BackgroundColor3 = glowColor,
				BackgroundTransparency = function()
					return 0.8 - 0.1 * pulse(style.PulseSpeed * 0.7 + i)
				end,
				Rotation = function()
					return baseAngle + clock() * style.RaySpeed
				end,

				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			})
		end
		return create("Frame")({
			Name = "Rays",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			table.unpack(lines),
		})
	end

	--== 4. проезжающий блик ==================================================
	local function sweep()
		if not style.Sweep then
			return nil
		end
		return create("Frame")({
			Name = "Sweep",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.26, 1.8),
			Rotation = 18,
			BorderSizePixel = 0,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.8,
			Position = function()
				-- едет -0.6 .. 1.6 за ~7 с, большую часть времени блик за кадром (пауза)
				local p = (clock() * 0.14) % 1
				return UDim2.fromScale(-0.6 + p * 2.2, 0.5)
			end,

			create("UIGradient")({
				Rotation = 0,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	--== 5. «постамент»: светящийся эллипс под мечом ==========================
	local function floorGlow()
		if style.Floor <= 0 then
			return nil
		end
		return create("Frame")({
			Name = "Floor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.9),
			Size = UDim2.fromScale(0.7, 0.14),
			BorderSizePixel = 0,
			BackgroundColor3 = glowColor,
			BackgroundTransparency = function()
				local breathe = if style.PulseSpeed > 0 then 0.8 + 0.2 * pulse(style.PulseSpeed) else 1
				return 1 - math.clamp(style.Floor * 0.55 * breathe, 0, 0.9)
			end,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		})
	end

	--== 6. частицы ===========================================================
	local function motes()
		if style.Motes <= 0 then
			return nil
		end
		local list = {}
		for i = 1, style.Motes do
			local speed = style.MoteSpeed * (0.7 + 0.6 * hash(i, 1))
			local phase = hash(i, 2)
			local function life(): number
				return (clock() * speed + phase) % 1
			end
			list[i] = create("Frame")({
				Name = `Mote{i}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(style.MoteSize, style.MoteSize),
				BorderSizePixel = 0,
				BackgroundColor3 = if style.Cycle then WHITE else rarityFx.lighten(style.Glow, 0.45),
				Position = function()
					local x = 0.12 + 0.76 * hash(i, 3) + math.sin(clock() * (0.7 + hash(i, 4)) + i) * 0.035
					return UDim2.fromScale(x, 1.04 - life() * 1.08)
				end,
				-- плавно проявляется и гаснет по жизни частицы
				BackgroundTransparency = function()
					return 1 - 0.8 * math.sin(math.pi * life())
				end,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			})
		end
		return create("Frame")({
			Name = "Motes",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			table.unpack(list),
		})
	end

	local function twinkles()
		if style.Twinkles <= 0 then
			return nil
		end
		local list = {}
		for i = 1, style.Twinkles do
			local speed = 1.1 + hash(i, 5) * 1.3
			local phase = hash(i, 6) * math.pi * 2
			list[i] = create("Frame")({
				Name = `Twinkle{i}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.14 + 0.72 * hash(i, 7), 0.12 + 0.6 * hash(i, 8)),
				Size = UDim2.fromOffset(5, 5),
				Rotation = 45,
				BorderSizePixel = 0,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = function()
					-- «вспыхивает» коротко: sin^6 — большую часть времени невидима
					local s = math.sin(clock() * speed + phase)
					return 1 - 0.95 * math.max(s, 0) ^ 6
				end,
			})
		end
		return create("Frame")({
			Name = "Twinkles",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			table.unpack(list),
		})
	end

	--== рамка: внутри границ (отступ 2px), чтобы чёрная обводка контейнера осталась ==
	local function rim()
		if not style.Rim then
			return nil
		end
		return create("Frame")({
			Name = "Rim",
			ZIndex = 2,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,

			create("UICorner")({ CornerRadius = UDim.new(0, math.max(radius.Offset - 1, 0)) }),
			create("UIStroke")({
				Thickness = 1.5,
				Color = if style.Cycle then glowColor else rarityFx.lighten(accent, 0.15),
				Transparency = function()
					local rimAlpha = style.Rim :: number
					return if style.PulseSpeed > 0 then rimAlpha + 0.12 * (1 - pulse(style.PulseSpeed)) else rimAlpha
				end,
			}),
		})
	end

	--== сборка ===============================================================
	-- Дети собираются списком: table.unpack в середине конструктора таблицы отдал бы
	-- только первое значение, а nil-слои (нет лучей/частиц) оставили бы дыры.
	local scene = {
		Name = "Scene",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		create("UICorner")({ CornerRadius = radius }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(style.Top, style.Bottom),
		}),
	}
	local function add(layer)
		if layer then
			table.insert(scene, layer)
		end
	end
	for _, layer in ipairs(glowLayers()) do
		add(layer)
	end
	add(rays())
	add(sweep())
	add(floorGlow())
	add(motes())
	add(twinkles())
	-- виньетка: низ темнее, верх слегка, центр остаётся светлым
	add(create("Frame")({
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0,

		create("UIGradient")({
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.8),
				NumberSequenceKeypoint.new(0.3, 1),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 0.55),
			}),
		}),
	}))

	local root = {
		Name = "RarityBackdrop",
		ZIndex = 1,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		-- CanvasGroup обрезает всё по скруглению (лучи/блик выходят за края)
		create("CanvasGroup")(scene),
	}
	local rimFrame = rim()
	if rimFrame then
		table.insert(root, rimFrame)
	end

	return create("Frame")(root)
end

return RarityBackdrop
