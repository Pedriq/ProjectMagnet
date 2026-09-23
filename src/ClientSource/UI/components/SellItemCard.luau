local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local ModelViewport = require(ReplicatedStorage.ClientSource.UI.components.ModelViewport)

local create = vide.create
local read = vide.read -- read(x): x() если источник, иначе x

local asset = Format.asset

--[[
	SellItemCard — строка-карточка в панели Sell Loot (по макету):

	  ┌───────────────────────────────────────────────┐
	  │ ┌────┐  Spirit Feather x2        [   Sell   ] │
	  │ │icon│  +$242T                   [   Lock   ] │
	  │ └────┘                                        │
	  └───────────────────────────────────────────────┘

	Слева — иконка предмета в белом квадрате; по центру — имя (цвет по редкости)
	с множителем «xN» и цена (уже с учётом множителя денег); справа — кнопки
	Sell (зелёная) и Lock (красная).

	Цена приходит готовой строкой (`PriceText`). ИКОНКИ предметов пока нет.
	Пока Locked() — вместо цены красным "Locked", кнопка Sell задизейблена,
	Lock превращается в Unlock, на иконке замочек. Блокировка — по имени
	предмета (вся стопка), источник правды — сервер (PlayerManagerService:
	ToggleItemLock), см. HUD.luau/SellPanel.luau.
]]

export type Props = {
	Name: string | () -> string,
	Count: number | () -> number, -- сколько предметов в стопке (>=1)
	PriceText: () -> string, -- уже с валютой и множителем, напр. "+$242T"
	NameColor: (Color3 | () -> Color3)?, -- цвет имени по редкости
	Model: () -> Instance?, -- модель предмета для 3D-превью; реактивно (карточка переиспользуется по индексу)

	Locked: (() -> boolean)?, -- предмет заблокирован от продажи (вместо цены — "Locked")
	OnSell: (() -> ())?,
	OnLock: (() -> ())?,

	LayoutOrder: number?,
}

local CARD_HEIGHT = 96
local ICON_SIZE = 72
local ICON_PAD = 12
local BUTTONS_WIDTH = 132

local CARD_COLOR = Color3.fromRGB(126, 208, 96)
local SELL_COLOR = Color3.fromRGB(70, 200, 64)
local LOCK_COLOR = Color3.fromRGB(232, 72, 72)
local PRICE_COLOR = Color3.fromRGB(60, 255, 90)

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = Color3.new(0, 0, 0),
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function SellItemCard(props: Props)
	local radius = UDim.new(0, 6)
	local infoLeft = ICON_PAD + ICON_SIZE + ICON_PAD

	local function locked(): boolean
		return props.Locked ~= nil and props.Locked() == true
	end

	local function nameText(): string
		local n = read(props.Count)
		local name = read(props.Name)
		return if n > 1 then `{name}  x{n}` else name
	end

	return create("Frame")({
		Name = "SellItemCard",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, -6, 0, CARD_HEIGHT),
		BackgroundColor3 = CARD_COLOR,

		create("UICorner")({ CornerRadius = radius }),
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

		--== иконка предмета ================================================
		create("Frame")({
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ICON_PAD, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = Color3.fromRGB(248, 250, 245),

			create("UICorner")({ CornerRadius = UDim.new(0, 5) }),
			create("UIStroke")({ Thickness = 2.5, Color = Color3.new(0, 0, 0), Transparency = 0.15 }),

			ModelViewport({
				Model = props.Model,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -8, 1, -8),
			}),

			-- замочек поверх иконки, пока предмет заблокирован
			create("TextLabel")({
				Name = "LockBadge",
				Visible = locked,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamBlack,
				Text = "🔒",
				TextScaled = true,
			}),
		}),

		--== имя + цена ====================================================
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

			create("TextLabel")({
				Name = "ItemName",
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				Font = Enum.Font.GothamBlack,
				TextSize = 22,
				TextColor3 = props.NameColor or Color3.fromRGB(250, 252, 245),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = nameText,

				textStroke(2),
			}),
			create("TextLabel")({
				Name = "Price",
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				Font = Enum.Font.GothamBlack,
				TextSize = 24,
				TextColor3 = function()
					return locked() and LOCK_COLOR or PRICE_COLOR
				end,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = function()
					return locked() and "Locked" or props.PriceText()
				end,

				textStroke(2.5),
			}),
		}),

		--== кнопки =======================================================
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
				Text = "Sell",
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 34),
				TextSize = 20,
				Color = SELL_COLOR,
				Disabled = locked,
				OnActivated = props.OnSell,
			}),
			WideButton({
				LayoutOrder = 2,
				Text = function()
					return if locked() then "Unlock" else "Lock"
				end,
				Size = UDim2.fromOffset(BUTTONS_WIDTH, 34),
				TextSize = 20,
				Color = LOCK_COLOR,
				OnActivated = props.OnLock,
			}),
		}),

		EdgeAccent({ Radius = radius }),
	})
end

return SellItemCard
