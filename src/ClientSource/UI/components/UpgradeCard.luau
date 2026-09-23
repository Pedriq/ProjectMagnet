local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)

local create = vide.create

local asset = Format.asset

--[[
	UpgradeCard — строка-карточка в панели Upgrades (по макету):

	  ┌───────────────────────────────────────────────┐
	  │ ┌────┐  Range        Lv.32     [  $21.9Qa   ] │
	  │ │icon│  +7.5% Atk. Radius      [  ⬡ 139     ] │
	  │ └────┘                                        │
	  └───────────────────────────────────────────────┘

	Слева — иконка в белом квадрате; по центру — название + уровень и статичный
	текст бонуса; справа — две кнопки: прокачать за Money и купить за донат.

	Чистый UI: все числа приходят готовыми источниками из UpgradesPanel.
	Иконки — из StatUpgradesConfig.Stats[key].Icon; Icon = "" рисует пустой квадрат.
]]

export type Props = {
	Title: string,
	Bonus: string, -- статичный текст бонуса, напр. "+10% Atk. Speed"
	Icon: string?, -- rbxassetid или "" (заведут позже)

	Level: () -> number,
	CostText: () -> string, -- уже с валютой, напр. "$21.9Qa"
	RobuxText: () -> string, -- подпись на кнопке доната, напр. "⬡ 139"

	MoneyDisabled: (() -> boolean)?, -- нет денег / макс. уровень
	OnBuyMoney: (() -> ())?,
	OnBuyRobux: (() -> ())?,

	LayoutOrder: number?,
}

local CARD_HEIGHT = 96
local ICON_SIZE = 72
local ICON_PAD = 12
local BUTTONS_WIDTH = 138

local CARD_COLOR = Color3.fromRGB(126, 208, 96)
local MONEY_COLOR = Color3.fromRGB(70, 200, 64) -- кнопка «за Money» всегда зелёная (в т.ч. в Disabled)
local ROBUX_COLOR = Color3.fromRGB(255, 190, 62)
local TITLE_COLOR = Color3.fromRGB(250, 252, 245)
local LEVEL_COLOR = Color3.fromRGB(232, 246, 220)
local BONUS_COLOR = Color3.fromRGB(250, 252, 245)

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = Color3.new(0, 0, 0),
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function UpgradeCard(props: Props)
	local radius = UDim.new(0, 6)
	local infoLeft = ICON_PAD + ICON_SIZE + ICON_PAD

	return create("Frame")({
		Name = "UpgradeCard",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, -6, 0, CARD_HEIGHT),
		BackgroundColor3 = CARD_COLOR,

		create("UICorner")({ CornerRadius = radius }),
		-- сочный верх, лёгкая тень к низу (тот же приём, что у пилюль/кнопок)
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.new(0.82, 0.82, 0.82)),
			}),
		}),
		create("UIStroke")({
			Thickness = 3,
			Color = Color3.new(0, 0, 0),
			Transparency = 0.1,
		}),
		create("ImageLabel")({
			Name = "Texture",
			ZIndex = 0,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(CARD_HEIGHT, CARD_HEIGHT),
			ImageTransparency = 0.76,
			Image = asset("137638295200351"),

			create("UICorner")({ CornerRadius = radius }),
		}),

		--== иконка в белом квадрате ========================================
		create("Frame")({
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ICON_PAD, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = Color3.fromRGB(248, 250, 245),

			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({ Thickness = 2.5, Color = Color3.new(0, 0, 0), Transparency = 0.15 }),

			create("ImageLabel")({
				Name = "Image",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -8),
				ScaleType = Enum.ScaleType.Fit,
				Image = asset(props.Icon),
			}),
		}),

		--== название + уровень + бонус ====================================
		create("Frame")({
			Name = "Info",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, infoLeft, 0, 0),
			Size = UDim2.new(1, -infoLeft - BUTTONS_WIDTH - 10, 1, 0),

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 4),
			}),

			-- строка: название + "Lv.N"
			create("Frame")({
				Name = "TitleRow",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),

				create("TextLabel")({
					Name = "Title",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.new(0.62, 0, 1, 0),
					Font = Enum.Font.GothamBlack,
					TextSize = 23,
					TextColor3 = TITLE_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = props.Title,

					textStroke(2),
				}),
				create("TextLabel")({
					Name = "Level",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0.62, 0.5),
					Size = UDim2.new(0.38, 0, 1, 0),
					Font = Enum.Font.GothamBlack,
					TextSize = 19,
					TextColor3 = LEVEL_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = function()
						return `Lv.{props.Level()}`
					end,

					textStroke(2),
				}),
			}),

			-- статичный бонус
			create("TextLabel")({
				Name = "Bonus",
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				Font = Enum.Font.GothamBlack,
				TextSize = 20,
				TextColor3 = BONUS_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = props.Bonus,

				textStroke(2),
			}),
		}),

		--== кнопки покупки ================================================
		create("Frame")({
			Name = "Buttons",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(BUTTONS_WIDTH, 78),
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
				Text = props.CostText,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 34),
				TextSize = 18,
				Color = MONEY_COLOR,
				DisabledColor = MONEY_COLOR, -- в Disabled тоже зелёная (просто притухает)
				TextureTransparency = 0.66,
				Disabled = props.MoneyDisabled,
				OnActivated = props.OnBuyMoney,
			}),
			WideButton({
				LayoutOrder = 2,
				Text = props.RobuxText,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 34),
				TextSize = 18,
				Color = ROBUX_COLOR,
				TextColor = Color3.fromRGB(255, 255, 255),
				TextureTransparency = 0.66,
				OnActivated = props.OnBuyRobux,
			}),
		}),

		EdgeAccent({ Radius = radius }),
	})
end

return UpgradeCard
