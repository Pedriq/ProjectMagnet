local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local TutorialPulse = require(ReplicatedStorage.ClientSource.UI.components.TutorialPulse)
local TutorialDim = require(ReplicatedStorage.ClientSource.UI.components.TutorialDim)
local RarityText = require(ReplicatedStorage.ClientSource.UI.components.RarityText)
local ModelViewport = require(ReplicatedStorage.ClientSource.UI.components.ModelViewport)
local RarityBackdrop = require(ReplicatedStorage.ClientSource.UI.components.RarityBackdrop)
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
	Фон ПРЕВЬЮ меча (квадрат слева) — свой для каждой редкости, см. RarityBackdrop.

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

	Purchasable: boolean, -- false у стартового FridgeMagnet (только Equip/Equipped)
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

	-- Купленный донатный (Game Pass) меч в панели Magnets: тёмно-синяя анимированная
	-- карточка с мягким бликом и свечением вместо цвета редкости (CardEffect игнорируется)
	Premium: boolean?,

	-- Подсветка туториала: пульсирующая рамка (+ плашка HighlightLabel), пока Highlight() == true
	Highlight: (() -> boolean)?,
	HighlightLabel: string?,
	-- Затемнение туториала: карточка гаснет, пока Dim() == true (подсвечена другая карточка)
	Dim: (() -> boolean)?,

	LayoutOrder: number?,
}

local CARD_HEIGHT = 112
local ICON_SIZE = 84
local ICON_PAD = 12
local BUTTONS_WIDTH = 150

local NAME_COLOR = Theme.Text
local MAGNETISM_COLOR = Theme.ElectricBright -- сила магнита = электрический синий
local MONEY_COLOR = Theme.ButtonMoney
local ROBUX_COLOR = Theme.ButtonGold
local EQUIP_COLOR = Theme.ButtonElectric
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- премиум (купленный OP-меч): тёмно-синяя схема
local NAVY_DEEP = Color3.fromRGB(10, 22, 54)
local NAVY_LIGHT = Color3.fromRGB(22, 56, 128)
local PREMIUM_ACCENT = Color3.fromRGB(110, 172, 255)

local PILL = UDim.new(0.5, 0) -- кнопки-«таблетки»: никаких квадратных углов на фоне скруглённого UI

local MAGNETISM_ICON = "82923936325309" -- та же иконка «силы», что в MultiplierRow

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
	local premium = props.Premium == true
	local cardEffect = if premium then 0 else (props.CardEffect or 0)
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

	--== премиум: тёмно-синяя анимированная карточка ========================
	-- Фон медленно «дышит» между двумя оттенками синего; блик проезжает раз в несколько
	-- секунд; мягкое свечение за иконкой и тонкая пульсирующая рамка. Всё приглушённое —
	-- заметно, но не слепит и не отвлекает от меча.
	local function premiumBackground()
		if not premium then
			return nil
		end
		return create("Frame")({
			Name = "PremiumBackground",
			ZIndex = 0,
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return NAVY_DEEP:Lerp(NAVY_LIGHT, 0.5 + 0.5 * math.sin(clock() * 0.6))
			end,

			create("UICorner")({ CornerRadius = radius }),
			vshade(),
		})
	end

	local function premiumFx()
		if not premium then
			return nil
		end
		return create("CanvasGroup")({
			Name = "PremiumFx",
			ZIndex = 2,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = radius }),

			-- свечение за иконкой меча
			create("Frame")({
				Name = "IconGlow",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, ICON_PAD + ICON_SIZE / 2, 0.5, 0),
				Size = UDim2.fromOffset(ICON_SIZE + 70, CARD_HEIGHT + 30),
				BorderSizePixel = 0,
				BackgroundColor3 = PREMIUM_ACCENT,
				BackgroundTransparency = function()
					return 0.86 - 0.05 * (0.5 + 0.5 * math.sin(clock() * 1.5))
				end,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),

			-- медленный диагональный блик (за ~6 с пересекает карточку и пропадает)
			create("Frame")({
				Name = "Shimmer",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 80, 2.2, 0),
				Rotation = 14,
				BorderSizePixel = 0,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.88,
				Position = function()
					local p = (clock() * 0.16) % 1
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
			}),
		})
	end

	local function premiumRim()
		if not premium then
			return nil
		end
		-- рамка внутри границ карточки (отступ 2px), чёрная внешняя обводка остаётся
		return create("Frame")({
			Name = "PremiumRim",
			ZIndex = 5,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,

			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({
				Thickness = 1.5,
				Color = PREMIUM_ACCENT,
				Transparency = function()
					return 0.4 + 0.2 * math.sin(clock() * 1.8)
				end,
			}),
		})
	end

	-- маленькая плашка «OP» в правом верхнем углу — отличает купленный донатный меч
	local function premiumTag()
		if not premium then
			return nil
		end
		return create("Frame")({
			Name = "OpTag",
			ZIndex = 5,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 7),
			Size = UDim2.fromOffset(38, 17),
			BackgroundColor3 = NAVY_DEEP,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("UIStroke")({ Thickness = 1.2, Color = PREMIUM_ACCENT, Transparency = 0.2 }),
			create("TextLabel")({
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBlack,
				Text = "OP",
				TextSize = 13,
				TextColor3 = rarityFx.lighten(PREMIUM_ACCENT, 0.55),
			}),
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
				CornerRadius = PILL,
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
				CornerRadius = PILL,
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
				CornerRadius = PILL,
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
		BackgroundColor3 = if premium then NAVY_DEEP else props.RarityColor,

		create("UICorner")({ CornerRadius = radius }),
		vshade(),
		create("UIStroke")({ Thickness = 3, Color = BLACK, Transparency = 0.1 }),
		-- подсветка туториала («купи этот магнит»)
		props.Highlight and TutorialPulse({ Active = props.Highlight, Label = props.HighlightLabel }) or nil,
		props.Dim and TutorialDim({ Active = props.Dim, CornerRadius = radius }) or nil,

		fxBackground(),
		premiumBackground(),

		create("ImageLabel")({
			Name = "Texture",
			ZIndex = 1,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(CARD_HEIGHT, CARD_HEIGHT),
			ImageTransparency = if premium
				then 0.88
				elseif cardEffect == 1 or cardEffect == 3 or cardEffect == 4 then 0.86
				else 0.76,
			Image = asset("119993804734501"),

			create("UICorner")({ CornerRadius = radius }),
		}),

		lightBars(),
		premiumFx(),
		premiumRim(),
		premiumTag(),

		--== иконка меча ===================================================
		create("Frame")({
			Name = "Icon",
			ZIndex = 3,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ICON_PAD, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = Theme.Steel300,

			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({ Thickness = 2.5, Color = BLACK, Transparency = 0.15 }),

			-- фон превью в стиле редкости (свечение, лучи, частицы — см. RarityBackdrop);
			-- сам меч выше по ZIndex и остаётся главным
			RarityBackdrop({ Rarity = if premium then "OP" else props.Rarity, Radius = UDim.new(0, 5) }),

			ModelViewport({
				ZIndex = 2,
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
