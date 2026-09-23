local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Surface = require(ReplicatedStorage.ClientSource.UI.components.Surface)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create

export type Props = {
	Title: string,
	Minutes: number,
	Price: number,
	Icon: string,
	Money: boolean?,
	LayoutOrder: number,
	ProductId: number?,
	OnBuy: ((productId: number) -> ())?,
}

local function BoostCard(props: Props)
	local money = props.Money == true
	local accent = if money then Color3.fromRGB(76, 242, 0) else Color3.fromRGB(255, 195, 35)
	local function label(name: string, text: string, y: number, height: number, color: Color3)
		return create("TextLabel")({
			Name = name,
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.04, y),
			Size = UDim2.fromScale(0.92, height),
			Font = Enum.Font.GothamBlack,
			Text = text,
			TextScaled = true,
			TextColor3 = color,
			create("UIStroke")({ Thickness = 2.5, Color = Color3.new(0, 0, 0) }),
		})
	end

	return create("Frame")({
		Name = `Boost{props.LayoutOrder}`,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(0.295, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		create("UICorner")({ CornerRadius = UDim.new(0.008, 0) }),
		create("UIStroke")({ Thickness = 3, Color = Color3.new(0, 0, 0) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(
				if money then Color3.fromRGB(221, 255, 202) else Color3.fromRGB(255, 253, 200),
				if money then Color3.fromRGB(44, 222, 19) else Color3.fromRGB(255, 161, 0)
			),
		}),
		label("Title", props.Title, 0.035, 0.12, accent),
		label("Duration", `{props.Minutes} MINUTES`, 0.195, 0.09, Color3.new(1, 1, 1)),
		create("ImageLabel")({
			Name = "BoostIcon",
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.16, 0.285),
			Size = UDim2.fromScale(0.68, 0.45),
			Image = Format.asset(props.Icon),
			ScaleType = Enum.ScaleType.Fit,
		}),
		create("Frame")({
			Name = "Price",
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.18, 0.76),
			Size = UDim2.fromScale(0.64, 0.18),
			WideButton({
				Text = `\u{E002}{props.Price}`,
				Size = UDim2.fromScale(1, 1),
				ScaleLayout = true,
				Color = Color3.fromRGB(99, 255, 0),
				TextureTransparency = 0.72,
				OnActivated = function()
					if props.OnBuy and props.ProductId then
						props.OnBuy(props.ProductId)
					end
				end,
			}),
		}),
		-- Текстура уже была (Surface даёт её по умолчанию). Два отдельных бага:
		-- 1) прозрачность 0.86 (14% непрозрачности) — почти не читалась, выровнял
		--    на те же 0.6, что у полоски тайтла Shop.
		-- 2) TileSize 0.085x0.075 давал плитку ~11x10px — на карточке ~132x140
		--    это 12x13 повторов, узор рассыпался в мелкий шум. 0.33x0.33 — плитка
		--    ~1/3 карточки, 3x3 повтора, тот же по ощущению масштаб, что у
		--    остальных карточек в проекте (SellItemCard/MagnetCard/UpgradeCard —
		--    там плитка размером с саму карточку по высоте).
		table.unpack(Surface({
			Radius = UDim.new(0.008, 0),
			TileSize = UDim2.fromScale(0.33, 0.33),
			TextureTransparency = 0.6,
			Highlight = 0,
			Shadow = 0,
		})),
	})
end

return BoostCard
