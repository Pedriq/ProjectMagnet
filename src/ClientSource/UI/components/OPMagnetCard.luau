local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Surface = require(ReplicatedStorage.ClientSource.UI.components.Surface)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local MagnetViewport = require(ReplicatedStorage.ClientSource.UI.components.MagnetViewport)
local RarityBackdrop = require(ReplicatedStorage.ClientSource.UI.components.RarityBackdrop)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = vide.create
local switch = vide.switch
local clock = rarityFx.clock

--[[
	OPMagnetCard — карточка донатного (Game Pass) меча в магазине. Премиум-вид, в духе
	секции платных зон: тёмная насыщенная база цвета редкости, анимированная рамка,
	«сцена» за мечом (RarityBackdrop: свечение, лучи, искры), проезжающий блик,
	пульсирующее свечение под ценой и плашка редкости.

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

type Palette = { Top: Color3, Bottom: Color3, Light: Color3 }

local PALETTES: { [string]: Palette } = {
	Secret = {
		Top = Color3.fromRGB(78, 14, 80),
		Bottom = Color3.fromRGB(24, 6, 38),
		Light = Color3.fromRGB(255, 190, 238),
	},
	Godly = {
		Top = Color3.fromRGB(28, 38, 92),
		Bottom = Color3.fromRGB(9, 13, 40),
		Light = Color3.fromRGB(255, 248, 200),
	},
}

local function pulse(speed: number): number
	return 0.5 + 0.5 * math.sin(clock() * speed)
end

local function OPMagnetCard(props: Props)
	local rarity = props.Rarity or (if props.Red then "Godly" else "Secret")
	local palette = PALETTES[rarity] or PALETTES.Secret
	local accent = RarityColors.get(rarity)

	local function stroke(thickness: number?)
		return create("UIStroke")({ Thickness = thickness or 2, Color = BLACK })
	end

	-- цвет акцента «дышит» между самим акцентом и светлым тоном палитры
	local function livingAccent(): Color3
		return accent:Lerp(palette.Light, 0.35 * pulse(1.6))
	end

	return create("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(0.465, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
		stroke(2.5),
		-- база: тёмный насыщенный верх -> почти чёрный низ (цвет редкости)
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(palette.Top, palette.Bottom),
		}),

		-- слой эффектов уровня карточки: блик + мягкие угловые свечения (внутри скругления)
		create("CanvasGroup")({
			Name = "Fx",
			ZIndex = 1,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = UDim.new(0, 10) }),

			-- свечение в правом верхнем углу (за плашкой редкости)
			create("Frame")({
				Name = "CornerGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.85, 0.12),
				Size = UDim2.fromScale(0.7, 0.55),
				BorderSizePixel = 0,
				BackgroundColor3 = accent,
				BackgroundTransparency = function()
					return 0.86 - 0.06 * pulse(1.3)
				end,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),

			-- диагональный блик по всей карточке раз в несколько секунд
			create("Frame")({
				Name = "Sweep",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(0.16, 2),
				Rotation = 18,
				BorderSizePixel = 0,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.82,
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
			BackgroundColor3 = palette.Bottom,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0.35, 0) }),
			create("UIStroke")({
				Thickness = 1.5,
				Color = livingAccent,
				Transparency = 0.1,
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
			BackgroundColor3 = palette.Bottom,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.03, 0.23),
			Size = UDim2.fromScale(0.42, 0.72),

			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			create("UIStroke")({
				Thickness = 2.5,
				Color = livingAccent,
				Transparency = 0.15,
			}),

			RarityBackdrop({ Rarity = rarity, Radius = UDim.new(0, 8) }),

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

		-- мягкое пульсирующее свечение под кнопкой цены (привлекает внимание, не перекрывает)
		create("Frame")({
			Name = "PriceGlow",
			ZIndex = 2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.7875, 0.845),
			Size = UDim2.fromScale(0.45, 0.26),
			BorderSizePixel = 0,
			BackgroundColor3 = accent,
			BackgroundTransparency = function()
				return 0.8 - 0.1 * pulse(2.2)
			end,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
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

		-- рамка внутри границ (отступ), пульсирует цветом редкости
		create("Frame")({
			Name = "Rim",
			ZIndex = 5,
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,

			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			create("UIStroke")({
				Thickness = 2,
				Color = livingAccent,
				Transparency = function()
					return 0.05 + 0.3 * (1 - pulse(1.8))
				end,
			}),
		}),

		table.unpack(Surface({
			Radius = UDim.new(0, 10),
			Texture = "rbxassetid://119993804734501",
			TileSize = UDim2.fromScale(0.2, 0.3),
			TextureTransparency = 0.88,
			Highlight = 0,
			Shadow = 0,
		})),
	})
end

return OPMagnetCard
