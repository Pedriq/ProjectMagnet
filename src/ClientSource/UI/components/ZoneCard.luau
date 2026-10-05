local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local clock = rarityFx.clock

local asset = Format.asset

--[[
	ZoneCard — карточка платной автоклик-зоны (Tesla Coil Zone) в секции Training Zones
	магазина (ShopPanel). Строка во всю ширину:

	  ┌──────────────────────────────────────────────────────────┐
	  │ ┌───────┐  x1000 Tesla Coil Zone              ┌────────┐ │
	  │ │ x1000 │  Auto-clicks with x1000 power       │ R$3999 │ │
	  │ └───────┘  while you stand inside             └────────┘ │
	  └──────────────────────────────────────────────────────────┘

	Чем выше Tier (1..5 — позиция по возрастанию множителя), тем «дороже» вид:
	  1 — холодный синий, ровная рамка
	  2 — изумрудный, рамка дышит, проезжает блик
	  3 — фиолетовый, рамка ярче, блик чаще
	  4 — золотой, искры, свечение бейджа
	  5 — малиновый/магента с переливом цвета, больше искр, пульсирующий бейдж

	Состояние «Owned» — зелёная кнопка и значок; то же состояние, что у касания зоны
	(Data.ownedZones), поэтому кнопка меняется сразу после покупки любым из способов.

	Всё рисуется Frame'ами, без внешних картинок (кроме общей тайловой текстуры проекта).
]]

export type Props = {
	Multiplier: number,
	Title: string,
	Price: number,
	Tier: number, -- 1..5, влияет на вид
	Owned: () -> boolean,
	OnBuy: (() -> ())?,
	LayoutOrder: number?,
}

type Palette = {
	Accent: Color3, -- рамка, свечение, лучи
	Light: Color3, -- светлый тон для текста множителя
	Dark: Color3, -- левый (тёмный) край фона
	Mid: Color3, -- правый край фона
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTES: { Palette } = {
	{ Accent = rgb(70, 170, 255), Light = rgb(190, 228, 255), Dark = rgb(12, 28, 56), Mid = rgb(24, 62, 112) },
	{ Accent = rgb(64, 230, 140), Light = rgb(188, 255, 214), Dark = rgb(8, 40, 28), Mid = rgb(16, 92, 60) },
	{ Accent = rgb(180, 112, 255), Light = rgb(228, 202, 255), Dark = rgb(30, 14, 62), Mid = rgb(70, 36, 130) },
	{ Accent = rgb(255, 196, 56), Light = rgb(255, 238, 168), Dark = rgb(56, 38, 6), Mid = rgb(130, 88, 10) },
	{ Accent = rgb(255, 84, 120), Light = rgb(255, 196, 214), Dark = rgb(52, 8, 28), Mid = rgb(136, 20, 62) },
}

local CARD_HEIGHT = 92
local BADGE_WIDTH = 112
local BUTTON_WIDTH = 150
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function hash(i: number, k: number): number
	return (math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1
end

local function pulse(speed: number): number
	return 0.5 + 0.5 * math.sin(clock() * speed)
end

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = BLACK,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function ZoneCard(props: Props)
	local tier = math.clamp(props.Tier, 1, #PALETTES)
	local palette = PALETTES[tier]
	local radius = UDim.new(0, 8)

	-- акцентный цвет; у верхнего тира переливается между малиновым и розово-оранжевым
	local function accent(): Color3
		if tier >= 5 then
			local hue = 0.96 + 0.1 * (0.5 + 0.5 * math.sin(clock() * 0.5)) -- ~0.96..1.06
			return Color3.fromHSV(hue % 1, 0.7, 1)
		end
		return palette.Accent
	end

	--== эффекты внутри карточки (обрезаются по скруглению CanvasGroup'ом) ======
	local function fxLayer()
		local children: { any } = {}

		-- свечение за бейджем множителя
		table.insert(
			children,
			create("Frame")({
				Name = "BadgeGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 12 + BADGE_WIDTH / 2, 0.5, 0),
				Size = UDim2.fromOffset(BADGE_WIDTH + 46, CARD_HEIGHT + 20),
				BorderSizePixel = 0,
				BackgroundColor3 = accent,
				BackgroundTransparency = function()
					local strength = 0.12 + 0.05 * tier
					return 1 - strength * (0.8 + 0.2 * pulse(1.4 + tier * 0.3))
				end,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			})
		)

		-- проезжающий блик (со 2-го тира, чем выше — тем чаще)
		if tier >= 2 then
			local speed = 0.08 + 0.03 * tier
			table.insert(
				children,
				create("Frame")({
					Name = "Sweep",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.new(0, 70, 2.2, 0),
					Rotation = 16,
					BorderSizePixel = 0,
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.82,
					Position = function()
						local p = (clock() * speed) % 1
						return UDim2.fromScale(-0.15 + p * 1.3, 0.5)
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
			)
		end

		-- искры (с 4-го тира): поднимаются и гаснут
		if tier >= 4 then
			local count = if tier >= 5 then 9 else 5
			for i = 1, count do
				local speed = 0.2 * (0.7 + 0.6 * hash(i, 1))
				local phase = hash(i, 2)
				local function life(): number
					return (clock() * speed + phase) % 1
				end
				table.insert(
					children,
					create("Frame")({
						Name = `Spark{i}`,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(3, 3),
						BorderSizePixel = 0,
						BackgroundColor3 = rarityFx.lighten(palette.Accent, 0.5),
						Position = function()
							local x = 0.04 + 0.5 * hash(i, 3) + math.sin(clock() * (0.8 + hash(i, 4)) + i) * 0.01
							return UDim2.fromScale(x, 1.06 - life() * 1.12)
						end,
						BackgroundTransparency = function()
							return 1 - 0.85 * math.sin(math.pi * life())
						end,

						create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
					})
				)
			end
		end

		return create("CanvasGroup")({
			Name = "Fx",
			ZIndex = 1,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = radius }),
			table.unpack(children),
		})
	end

	--== левый бейдж: большой множитель ==========================================
	local function badge()
		return create("Frame")({
			Name = "Badge",
			ZIndex = 3,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(BADGE_WIDTH, CARD_HEIGHT - 24),
			BackgroundColor3 = palette.Dark,
			BackgroundTransparency = 0.1,

			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			create("UIStroke")({
				Thickness = 2,
				Color = accent,
				Transparency = function()
					return 0.1 + 0.25 * (1 - pulse(2 + tier * 0.4))
				end,
			}),

			create("TextLabel")({
				Name = "Multiplier",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromScale(0.92, 0.6),
				Font = Enum.Font.GothamBlack,
				Text = `x{props.Multiplier}`,
				TextScaled = true,
				TextColor3 = WHITE,

				textStroke(2.5),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(WHITE, palette.Light),
				}),
			}),
			create("TextLabel")({
				Name = "Caption",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.94),
				Size = UDim2.fromScale(0.9, 0.22),
				Font = Enum.Font.GothamBold,
				Text = "ZONE",
				TextScaled = true,
				TextColor3 = palette.Light,
				TextTransparency = 0.15,
			}),
		})
	end

	--== сборка ==================================================================
	local infoLeft = 12 + BADGE_WIDTH + 14

	return create("Frame")({
		Name = `Zone_x{props.Multiplier}`,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = radius }),
		-- фон: тёмный слева -> насыщенный справа (к кнопке)
		create("UIGradient")({
			Rotation = 0,
			Color = ColorSequence.new(palette.Dark, palette.Mid),
		}),
		-- рамка: «дышит» со 2-го тира, на верхнем переливается
		create("UIStroke")({
			Thickness = if tier >= 3 then 3 else 2.5,
			Color = accent,
			Transparency = function()
				if tier < 2 then
					return 0.3
				end
				return 0.08 + 0.3 * (1 - pulse(1.2 + tier * 0.35))
			end,
		}),

		create("ImageLabel")({
			Name = "Texture",
			ZIndex = 0,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(CARD_HEIGHT, CARD_HEIGHT),
			ImageTransparency = 0.9,
			Image = asset("119993804734501"),

			create("UICorner")({ CornerRadius = radius }),
		}),

		fxLayer(),
		badge(),

		--== название + описание ==================================================
		create("Frame")({
			Name = "Info",
			ZIndex = 3,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, infoLeft, 0, 0),
			Size = UDim2.new(1, -infoLeft - BUTTON_WIDTH - 24, 1, 0),

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 3),
			}),

			create("TextLabel")({
				Name = "Title",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 28),
				Font = Enum.Font.GothamBlack,
				Text = props.Title,
				TextSize = 24,
				TextColor3 = WHITE,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,

				textStroke(2),
			}),
			create("TextLabel")({
				Name = "Description",
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 36),
				Font = Enum.Font.GothamBold,
				Text = `Auto-clicks with x{props.Multiplier} power while you stand inside`,
				TextSize = 15,
				TextColor3 = palette.Light,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,

				textStroke(1.5),
			}),
		}),

		--== кнопка: цена или Owned ==================================================
		create("Frame")({
			Name = "Action",
			ZIndex = 3,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON_WIDTH, 48),

			WideButton({
				Text = function()
					return if props.Owned() then "Owned" else `\u{E002}{props.Price}`
				end,
				Size = UDim2.fromScale(1, 1),
				TextSize = 22,
				Color = Theme.ShopBuy,
				DisabledColor = Theme.ButtonMoney, -- Owned: кнопка Disabled -> зелёная
				DisabledTextTransparency = 0,
				TextureTransparency = 0.66,
				Disabled = props.Owned,
				OnActivated = props.OnBuy,
			}),
		}),
	})
end

return ZoneCard
