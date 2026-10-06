local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Surface = require(ReplicatedStorage.ClientSource.UI.components.Surface)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local MagnetViewport = require(ReplicatedStorage.ClientSource.UI.components.MagnetViewport)
local RarityBackdrop = require(ReplicatedStorage.ClientSource.UI.components.RarityBackdrop)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local switch = vide.switch
local clock = rarityFx.clock

--[[
	OPMagnetCard — карточка донатного (Game Pass) меча в магазине. Премиум-вид в стиле
	игрушечного LEGO-пластика: яркий глянцевый цвет редкости, скруглённые формы, глянцевая
	полоса сверху, тёмная кромка снизу, «ячейка» под мечом и редкий мягкий блик.

	Кнопка внизу карточки зависит от состояния (как у MagnetCard):
	  не куплен → цена за Robux (покупка Game Pass, см. ShopPanel/MagnetGamePassPurchaseHandler)
	  куплен    → Equip
	  надет     → Equipped (погашенная)

	Все эффекты лежат внутри границ карточки: фон/блик — в CanvasGroup со скруглением,
	рамка — отступом внутрь, всё в долях размера (на любом экране не вылезает).
]]
export type Props = {
	Name: string,
	Rarity: string?, -- "Secret" / "Godly" (MagnetData[..].Rare): задаёт палитру и сцену; по умолч. Secret
	-- Кандидаты имени модели в ReplicatedStorage.Assets.Magnets, в порядке
	-- приоритета (см. MagnetData.assetNameCandidates) — неизвестно заранее,
	-- назван ли ассет в Studio по Display, по старому Name или по ключу.
	-- По умолчанию = { Name }.
	ModelNames: { string }?,
	Bonus: number,
	Price: number,
	Red: boolean?, -- устарело: вид теперь задаёт Rarity
	LayoutOrder: number,
	Owned: () -> boolean,
	Equipped: () -> boolean,
	OnBuy: (() -> ())?,
	OnEquip: (() -> ())?,
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PILL = UDim.new(0.5, 0) -- кнопки-«таблетки»: в стиле остального скруглённого UI, без квадратных углов

-- Глянцевый игрушечный пластик: яркий чистый цвет сверху, насыщенный снизу, тёмная кромка того же тона
type Palette = { Top: Color3, Bottom: Color3, Edge: Color3, Light: Color3 }

local PALETTES: { [string]: Palette } = {
	Secret = {
		Top = Color3.fromRGB(208, 126, 255),
		Bottom = Color3.fromRGB(130, 56, 206),
		Edge = Color3.fromRGB(68, 26, 122),
		Light = Color3.fromRGB(250, 232, 255),
	},
	Godly = {
		Top = Color3.fromRGB(255, 226, 96),
		Bottom = Color3.fromRGB(242, 152, 18),
		Edge = Color3.fromRGB(140, 76, 6),
		Light = Color3.fromRGB(255, 248, 214),
	},
}

local function OPMagnetCard(props: Props)
	local rarity = props.Rarity or (if props.Red then "Godly" else "Secret")
	local palette = PALETTES[rarity] or PALETTES.Secret

	local function stroke(thickness: number?)
		return create("UIStroke")({ Thickness = thickness or 2, Color = BLACK })
	end

	return create("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(0.465, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		create("UICorner")({ CornerRadius = UDim.new(0, 14) }),
		-- шов игрушки: тёмная кромка того же оттенка вместо чёрной рамки
		create("UIStroke")({ Thickness = 3.5, Color = palette.Edge }),
		-- база: яркий пластик, чуть темнее к низу
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(palette.Top:Lerp(palette.Bottom, 0.35), palette.Bottom),
		}),

		-- слой эффектов уровня карточки: глянец, нижняя «губа», редкий мягкий блик
		create("CanvasGroup")({
			Name = "Fx",
			ZIndex = 1,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = UDim.new(0, 14) }),

			-- глянцевая полоса вдоль верхней кромки
			create("Frame")({
				Name = "Gloss",
				Position = UDim2.fromScale(0.04, 0.02),
				Size = UDim2.fromScale(0.92, 0.07),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),

			-- нижняя кромка кирпичика — даёт объём
			create("Frame")({
				Name = "Lip",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0.06),
				BackgroundColor3 = palette.Edge,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
			}),

			-- диагональный блик по всей карточке раз в несколько секунд
			create("Frame")({
				Name = "Sweep",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(0.16, 2),
				Rotation = 18,
				BorderSizePixel = 0,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.9,
				Position = function()
					local p = (clock() * 0.12) % 1
					return UDim2.fromScale(-0.2 + p * 1.4, 0.5)
				end,

				create("UIGradient")({
					Rotation = 0,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),

		-- название
		create("TextLabel")({
			Name = "Title",
			ZIndex = 4,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.035, 0.045),
			Size = UDim2.fromScale(0.6, 0.17),
			Font = Enum.Font.GothamBlack,
			Text = props.Name,
			TextScaled = true,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			stroke(2),
		}),

		-- плашка редкости: «SECRET» / «GODLY» + пометка донатного меча
		create("Frame")({
			Name = "RarityTag",
			ZIndex = 4,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(0.965, 0.06),
			Size = UDim2.fromScale(0.3, 0.125),
			BackgroundColor3 = palette.Edge,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke")({
				Thickness = 1.5,
				Color = palette.Light,
				Transparency = 0.35,
			}),
			create("ImageLabel")({
				Name = "Texture",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = "rbxassetid://119993804734501",
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromScale(0.3, 1),
				ImageTransparency = 0.65,

				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			}),
			create("TextLabel")({
				Name = "Label",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBlack,
				Text = string.upper(rarity),
				TextScaled = true,
				TextColor3 = WHITE,
				create("UIPadding")({
					PaddingTop = UDim.new(0.16, 0),
					PaddingBottom = UDim.new(0.16, 0),
				}),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(WHITE, palette.Light),
				}),
			}),
		}),

		-- «сцена» за мечом: рамка с цветом редкости, внутри фон-эффект + превью меча
		create("Frame")({
			Name = "Sword",
			ZIndex = 2,
			BackgroundColor3 = palette.Edge,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.03, 0.23),
			Size = UDim2.fromScale(0.42, 0.72),

			create("UICorner")({ CornerRadius = UDim.new(0, 12) }),
			-- утопленная «ячейка» под меч: светлая кромка как у пластикового углубления
			create("UIStroke")({
				Thickness = 3,
				Color = palette.Light,
				Transparency = 0.25,
			}),

			RarityBackdrop({ Rarity = rarity, Radius = UDim.new(0, 12) }),

			-- фактура пластика поверх сцены (под мечом): тонкая, не спорит с превью
			create("ImageLabel")({
				Name = "Texture",
				ZIndex = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = "rbxassetid://119993804734501",
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromScale(0.3, 0.2),
				ImageTransparency = 0.7,

				create("UICorner")({ CornerRadius = UDim.new(0, 12) }),
			}),

			-- вьюпорт в обёртке: ему нужен ZIndex выше фона-сцены
			create("Frame")({
				Name = "Viewport",
				ZIndex = 2,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				MagnetViewport(props.ModelNames or { props.Name }),
			}),
		}),

		create("TextLabel")({
			Name = "Bonus",
			ZIndex = 3,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.48, 0.265),
			Size = UDim2.fromScale(0.49, 0.34),
			Font = Enum.Font.GothamBlack,
			Text = `{props.Bonus}% better\nthan your\nbest Cutter`,
			TextScaled = true,
			TextColor3 = WHITE,
			stroke(2),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(WHITE, palette.Light),
			}),
		}),

		create("Frame")({
			Name = "Price",
			ZIndex = 3,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.61, 0.745),
			Size = UDim2.fromScale(0.355, 0.2),

			switch(function()
				if not props.Owned() then
					return "buy"
				end
				return props.Equipped() and "equipped" or "equip"
			end)({
				buy = function()
					return WideButton({
						Text = `\u{E002}{props.Price}`,
						Size = UDim2.fromScale(1, 1),
						ScaleLayout = true,
						CornerRadius = PILL,
						Color = Theme.ShopBuy,
						TextureTransparency = 0.72,
						OnActivated = props.OnBuy,
					})
				end,
				equip = function()
					return WideButton({
						Text = "Equip",
						Size = UDim2.fromScale(1, 1),
						ScaleLayout = true,
						CornerRadius = PILL,
						Color = Theme.ShopBuy,
						TextureTransparency = 0.72,
						OnActivated = props.OnEquip,
					})
				end,
				equipped = function()
					return WideButton({
						Text = "Equipped",
						Size = UDim2.fromScale(1, 1),
						ScaleLayout = true,
						CornerRadius = PILL,
						Color = Theme.ShopBuy,
						DisabledColor = Theme.ShopBuy,
						TextureTransparency = 0.72,
						Disabled = true,
					})
				end,
			}),
		}),

		table.unpack(Surface({
			Radius = UDim.new(0, 14),
			Texture = "rbxassetid://119993804734501",
			TileSize = UDim2.fromScale(0.2, 0.3),
			TextureTransparency = 0.8,
			Highlight = 0,
			Shadow = 0,
		})),
	})
end

return OPMagnetCard
