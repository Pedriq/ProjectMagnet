local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local RarityText = require(ReplicatedStorage.ClientSource.UI.components.RarityText)
local ModelViewport = require(ReplicatedStorage.ClientSource.UI.components.ModelViewport)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local switch = vide.switch

local asset = Format.asset
local clock = rarityFx.clock

--[[
	MagnetCard — толстая карточка меча в панели «Cutters» (по макету):

	  ┌──────────────────────────────────────────────────────┐
	  │ ┌─────┐  Sword Saw                     [   $280M   ]  │
	  │ │ img │  Legendary                     [   R$ 799  ]  │
	  │ └─────┘  💪 +267K Magnetism                            │
	  └──────────────────────────────────────────────────────┘

	Правая часть зависит от состояния:
	  не куплен  → две кнопки: цена за Money (зелёная) + цена за Robux (золотая)
	  куплен     → одна кнопка Equip (зелёная)
	  надет      → Equipped (погашенная)

	До Mythic (CardEffect = 0) фон карточки — цвет редкости.

	Эффекты (Mythic и выше), TextEffect/CardEffect из MagnetData.effectsFor():
	  Текст (лейбл редкости) — см. components/RarityText.
	  Карта (CardEffect), каждый — самостоятельный, не комбинируется:
	    1 — фон пульсирует светлее<->темнее (оттенок редкости)
	    2 — по карточке едут 2 толстые полосы света (фон остаётся цветом редкости)
	    3 — фон плавно перебирает разные цвета
	    4 — фон плавно перебирает цвета радуги (как на макете у Mythic)
]]

export type Props = {
	Display: string | () -> string,
	Rarity: string,
	RarityColor: Color3,
	MagnetismText: string | () -> string,
	Model: Instance?, -- модель меча для 3D-превью в карточке

	Purchasable: boolean, -- false у стартового Stick (только Equip/Equipped)
	Owned: () -> boolean,
	Equipped: () -> boolean,

	MoneyText: () -> string,
	MoneyDisabled: (() -> boolean)?,
	RobuxText: () -> string,

	OnBuyMoney: (() -> ())?,
	OnBuyRobux: (() -> ())?,
	OnEquip: (() -> ())?,

	TextEffect: number?,
	CardEffect: number?,

	LayoutOrder: number?,
}

local CARD_HEIGHT = 112
local ICON_SIZE = 84
local ICON_PAD = 12
local BUTTONS_WIDTH = 150

local NAME_COLOR = Color3.fromRGB(250, 252, 245)
local MAGNETISM_COLOR = Color3.fromRGB(250, 252, 245)
local MONEY_COLOR = Color3.fromRGB(70, 200, 64)
local ROBUX_COLOR = Color3.fromRGB(255, 190, 62)
local EQUIP_COLOR = Color3.fromRGB(70, 200, 64)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local MAGNETISM_ICON = "96772289336842" -- та же иконка «силы», что в MultiplierRow

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = BLACK,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- одна толстая полоса света, едет слева направо; края растушёваны по ширине
local function shineBar(phase: number, width: number, transparency: number)
	return create("Frame")({
		BackgroundColor3 = WHITE,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 12,
		Size = UDim2.new(0, width, 1.5, 0),
		Position = function()
			-- -0.15..1.15: полностью заезжает и съезжает; CanvasGroup обрезает по скруглению
			local p = ((clock() * 0.3) + phase) % 1.3 - 0.15
			return UDim2.fromScale(p, 0.5)
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

local function MagnetCard(props: Props)
	local radius = UDim.new(0, 6)
	local infoLeft = ICON_PAD + ICON_SIZE + ICON_PAD
	local cardEffect = props.CardEffect or 0
	local rColor = props.RarityColor

	-- вертикальная растушёвка «верх сочный / низ в тень» — как у остальных карточек
	local function vshade()
		return create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, WHITE),
				ColorSequenceKeypoint.new(0.55, WHITE),
				ColorSequenceKeypoint.new(1, Color3.new(0.82, 0.82, 0.82)),
			}),
		})
	end

	--== фон-эффект (CardEffect 1/3/4) =====================================
	local function fxBackground()
		if cardEffect ~= 1 and cardEffect ~= 3 and cardEffect ~= 4 then
			return nil
		end

		local gradientChild
		local bg: (() -> Color3) | Color3

		if cardEffect == 1 then
			local light = rarityFx.lighten(rColor, 0.22)
			local dark = rarityFx.darken(rColor, 0.3)
			bg = function()
				return light:Lerp(dark, math.sin(clock() * 1.4) * 0.5 + 0.5)
			end
			gradientChild = vshade()
		elseif cardEffect == 3 then
			bg = function()
				return rarityFx.cycleColor(clock() * 0.06)
			end
			gradientChild = vshade()
		else -- 4: радуга
			bg = WHITE
			gradientChild = create("UIGradient")({
				Rotation = 0,
				Color = function()
					return rarityFx.rainbowSequence((clock() * 0.08) % 1, 0.7, 1)
				end,
			})
		end

		return create("Frame")({
			Name = "FxBackground",
			ZIndex = 0,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = bg,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = radius }),
			gradientChild,
		})
	end

	--== CardEffect 2: 2 толстые полосы света, самостоятельный эффект ========
	-- CanvasGroup обрезает содержимое по скруглению — свет не вылезает за края.
	local function lightBars()
		if cardEffect ~= 2 then
			return nil
		end
		return create("CanvasGroup")({
			Name = "LightBars",
			ZIndex = 2,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			GroupTransparency = 0,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = radius }),
			shineBar(0.0, 68, 0.32),
			shineBar(0.42, 50, 0.42),
		})
	end

	--== правая часть: кнопки по состоянию ================================
	local function buyButtons()
		return create("Frame")({
			Name = "Buy",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
			}),

			WideButton({
				LayoutOrder = 1,
				Text = props.MoneyText,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 36),
				TextSize = 18,
				Color = MONEY_COLOR,
				DisabledColor = MONEY_COLOR,
				TextColor = WHITE,
				TextureTransparency = 0.66,
				Disabled = props.MoneyDisabled,
				OnActivated = props.OnBuyMoney,
			}),
			WideButton({
				LayoutOrder = 2,
				Text = props.RobuxText,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 36),
				TextSize = 18,
				Color = ROBUX_COLOR,
				TextColor = WHITE,
				TextureTransparency = 0.66,
				OnActivated = props.OnBuyRobux,
			}),
		})
	end

	local function singleButton(text: string, disabled: boolean)
		return create("Frame")({
			Name = "Single",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			WideButton({
				Text = text,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 44),
				TextSize = 20,
				Color = EQUIP_COLOR,
				DisabledColor = EQUIP_COLOR,
				TextureTransparency = 0.66,
				Disabled = disabled,
				OnActivated = if disabled then nil else props.OnEquip,
			}),
		})
	end

	local function buttonState(): string
		if props.Purchasable and not props.Owned() then
			return "buy"
		end
		return props.Equipped() and "equipped" or "equip"
	end

	return create("Frame")({
		Name = "MagnetCard",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, -6, 0, CARD_HEIGHT),
		BackgroundColor3 = props.RarityColor,

		create("UICorner")({ CornerRadius = radius }),
		vshade(),
		create("UIStroke")({ Thickness = 3, Color = BLACK, Transparency = 0.1 }),

		fxBackground(),

		create("ImageLabel")({
			Name = "Texture",
			ZIndex = 1,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(CARD_HEIGHT, CARD_HEIGHT),
			ImageTransparency = if cardEffect == 1 or cardEffect == 3 or cardEffect == 4 then 0.86 else 0.76,
			Image = asset("137638295200351"),

			create("UICorner")({ CornerRadius = radius }),
		}),

		lightBars(),

		--== иконка меча ===================================================
		create("Frame")({
			Name = "Icon",
			ZIndex = 3,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ICON_PAD, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = Color3.fromRGB(248, 250, 245),

			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({ Thickness = 2.5, Color = BLACK, Transparency = 0.15 }),

			ModelViewport({
				Model = props.Model,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -10, 1, -10),
				FieldOfView = 7,
				Padding = 1.05,
			}),
		}),

		--== имя + редкость + сила ========================================
		create("Frame")({
			Name = "Info",
			ZIndex = 3,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, infoLeft, 0, 0),
			Size = UDim2.new(1, -infoLeft - BUTTONS_WIDTH - 12, 1, 0),

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 3),
			}),

			create("TextLabel")({
				Name = "Name",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 28),
				Font = Enum.Font.GothamBlack,
				TextSize = 25,
				TextColor3 = NAME_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = props.Display,

				textStroke(2.5),
			}),

			RarityText({
				LayoutOrder = 2,
				Text = props.Rarity,
				Color = props.RarityColor,
				Effect = props.TextEffect or 0,
				TextSize = 18,
				Size = UDim2.new(1, 0, 0, 20),
			}),

			create("Frame")({
				Name = "MagnetismRow",
				LayoutOrder = 3,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 5),
				}),

				create("ImageLabel")({
					Name = "Icon",
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(22, 22),
					ScaleType = Enum.ScaleType.Fit,
					Image = asset(MAGNETISM_ICON),
				}),
				create("TextLabel")({
					Name = "Value",
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 0, 1, 0),
					Font = Enum.Font.GothamBlack,
					TextSize = 20,
					TextColor3 = MAGNETISM_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = props.MagnetismText,

					textStroke(2),
				}),
			}),
		}),

		--== кнопки =======================================================
		create("Frame")({
			Name = "Buttons",
			ZIndex = 3,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(BUTTONS_WIDTH, CARD_HEIGHT - 20),
			BackgroundTransparency = 1,

			switch(buttonState)({
				buy = buyButtons,
				equip = function()
					return singleButton("Equip", false)
				end,
				equipped = function()
					return singleButton("Equipped", true)
				end,
			}),
		}),

		EdgeAccent({ Radius = radius, ZIndex = 4 }),
	})
end

return MagnetCard
