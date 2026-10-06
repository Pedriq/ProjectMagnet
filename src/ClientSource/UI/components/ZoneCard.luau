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

	Вид — глянцевый игрушечный пластик (LEGO): яркие чистые цвета, скруглённые формы,
	глянцевая полоса сверху, тёмная «губа» снизу для объёма, бейдж множителя — кирпичик
	с шипами. Никакого неона: свечения и пульсации убраны.

	Чем выше Tier (1..5 — позиция по возрастанию множителя), тем «дороже» цвет:
	  1 — синий, 2 — зелёный, 3 — фиолетовый (+ редкий мягкий блик),
	  4 — жёлто-оранжевый, 5 — красно-розовый.

	Состояние «Owned» — зелёная кнопка; то же состояние, что у касания зоны
	(Data.ownedZones), поэтому кнопка меняется сразу после покупки любым из способов.

	Всё рисуется Frame'ами, без внешних картинок (кроме общей тайловой текстуры проекта).
]]

export type Props = {
	Multiplier: number,
	Title: string,
	Price: number,
	Tier: number, -- 1..5, влияет на цвет пластика
	Owned: () -> boolean,
	OnBuy: (() -> ())?,
	LayoutOrder: number?,
}

type Palette = {
	Top: Color3, -- светлый верх пластика (бейдж)
	Bottom: Color3, -- насыщенный низ (бейдж и фон карточки)
	Edge: Color3, -- тёмная кромка того же оттенка (шов, объём)
	Light: Color3, -- светлый тон для подписи
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTES: { Palette } = {
	{ Top = rgb(112, 198, 255), Bottom = rgb(34, 126, 232), Edge = rgb(14, 64, 150), Light = rgb(228, 245, 255) },
	{ Top = rgb(124, 232, 130), Bottom = rgb(40, 172, 74), Edge = rgb(16, 90, 40), Light = rgb(228, 255, 228) },
	{ Top = rgb(196, 150, 255), Bottom = rgb(128, 74, 222), Edge = rgb(66, 32, 130), Light = rgb(242, 228, 255) },
	{ Top = rgb(255, 222, 84), Bottom = rgb(255, 152, 24), Edge = rgb(150, 80, 6), Light = rgb(255, 247, 206) },
	{ Top = rgb(255, 132, 150), Bottom = rgb(234, 54, 84), Edge = rgb(130, 18, 40), Light = rgb(255, 224, 230) },
}

local CARD_HEIGHT = 92
local BADGE_WIDTH = 112
local BUTTON_WIDTH = 150
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = BLACK,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- «Шипы» LEGO сверху кирпича: маленькие скруглённые бруски с бликом
local function studs(count: number, palette: Palette)
	local list: { any } = {}
	for i = 1, count do
		table.insert(
			list,
			create("Frame")({
				Name = `Stud{i}`,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(i / (count + 1), 0, 0, 3),
				Size = UDim2.fromOffset(20, 9),
				BackgroundColor3 = palette.Top,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIStroke")({ Thickness = 2, Color = palette.Edge }),
				create("Frame")({
					Name = "Gloss",
					Position = UDim2.fromScale(0.15, 0.15),
					Size = UDim2.fromScale(0.7, 0.25),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,

					create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				}),
			})
		)
	end
	return list
end

local function ZoneCard(props: Props)
	local tier = math.clamp(props.Tier, 1, #PALETTES)
	local palette = PALETTES[tier]
	local radius = UDim.new(0, 14)
	local face = palette.Bottom:Lerp(palette.Edge, 0.22)

	--== мягкие эффекты внутри карточки (обрезаются по скруглению CanvasGroup'ом) ======
	local function fxLayer()
		local children: { any } = {
			-- глянец: светлая полоса вдоль верхней кромки
			create("Frame")({
				Name = "Gloss",
				Position = UDim2.fromOffset(8, 5),
				Size = UDim2.new(1, -16, 0, 12),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.8,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),
			-- «нижняя губа» кирпича: тёмная кромка снизу даёт объём
			create("Frame")({
				Name = "Lip",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundColor3 = palette.Edge,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}),
		}

		-- редкий мягкий блик (с 3-го тира)
		if tier >= 3 then
			table.insert(
				children,
				create("Frame")({
					Name = "Sweep",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.new(0, 60, 2.2, 0),
					Rotation = 16,
					BorderSizePixel = 0,
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.9,
					Position = function()
						local p = (clock() * 0.1) % 1
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

	--== левый бейдж: пластиковый кирпичик с шипами и большим множителем ===============
	local function badge()
		return create("Frame")({
			Name = "Badge",
			ZIndex = 3,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 4),
			Size = UDim2.fromOffset(BADGE_WIDTH, CARD_HEIGHT - 30),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
			create("UIStroke")({ Thickness = 2.5, Color = palette.Edge }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(palette.Top, palette.Bottom),
			}),

			table.unpack(studs(3, palette)),

			-- та же тайловая текстура, что на кнопках: едва заметная фактура пластика
			create("ImageLabel")({
				Name = "Texture",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(40, 40),
				ImageTransparency = 0.6,
				Image = asset("119993804734501"),

				create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
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

				textStroke(1.5),
			}),
		})
	end

	--== сборка ==================================================================
	local infoLeft = 14 + BADGE_WIDTH + 14

	return create("Frame")({
		Name = `Zone_x{props.Multiplier}`,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = radius }),
		-- фон: насыщенный пластик, чуть темнее к низу
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(palette.Bottom, face),
		}),
		-- обводка: тёмный тон того же цвета, как шов у игрушки
		create("UIStroke")({
			Thickness = 3,
			Color = palette.Edge,
		}),

		create("ImageLabel")({
			Name = "Texture",
			ZIndex = 0,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(CARD_HEIGHT, CARD_HEIGHT),
			ImageTransparency = 0.7,
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
				TextColor3 = WHITE,
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
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON_WIDTH, 48),

			WideButton({
				Text = function()
					return if props.Owned() then "Owned" else `\u{E002}{props.Price}`
				end,
				Size = UDim2.fromScale(1, 1),
				TextSize = 22,
				CornerRadius = UDim.new(0.5, 0),
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
