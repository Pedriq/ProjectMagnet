local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Surface = require(ReplicatedStorage.ClientSource.UI.components.Surface)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local WeaponViewport = require(ReplicatedStorage.ClientSource.UI.components.WeaponViewport)

local create = vide.create
local switch = vide.switch

--[[
	Кнопка внизу карточки зависит от состояния (как у WeaponCard):
	  не куплен → цена за Robux (покупка Game Pass, см. ShopPanel/WeaponGamePassPurchaseHandler)
	  куплен    → Equip
	  надет     → Equipped (погашенная)
]]
export type Props = {
	Name: string,
	Bonus: number,
	Price: number,
	Red: boolean?,
	LayoutOrder: number,
	Owned: () -> boolean,
	Equipped: () -> boolean,
	OnBuy: (() -> ())?,
	OnEquip: (() -> ())?,
}

local function OPSwordCard(props: Props)
	local function stroke()
		return create("UIStroke")({ Thickness = 2, Color = Color3.new(0, 0, 0) })
	end
	return create("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(0.465, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		stroke(),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(
				if props.Red then Color3.fromRGB(255, 0, 0) else Color3.fromRGB(255, 253, 226),
				if props.Red then Color3.fromRGB(58, 16, 20) else Color3.fromRGB(255, 230, 0)
			),
		}),
		create("TextLabel")({
			Name = "Title",
			ZIndex = 3,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.035, 0.045),
			Size = UDim2.fromScale(0.93, 0.17),
			Font = Enum.Font.GothamBlack,
			Text = props.Name,
			TextScaled = true,
			TextColor3 = if props.Red then Color3.fromRGB(215, 0, 0) else Color3.fromRGB(255, 211, 111),
			stroke(),
		}),
		create("Frame")({
			Name = "Sword",
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.025, 0.23),
			Size = UDim2.fromScale(0.42, 0.73),
			WeaponViewport(props.Name),
		}),
		create("TextLabel")({
			Name = "Bonus",
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.47, 0.265),
			Size = UDim2.fromScale(0.49, 0.34),
			Font = Enum.Font.GothamBlack,
			Text = `{props.Bonus}% better\nthan your\nbest Cutter`,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			stroke(),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 0), Color3.fromRGB(255, 168, 0)),
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
						Color = Color3.fromRGB(99, 255, 0),
						TextureTransparency = 0.72,
						OnActivated = props.OnBuy,
					})
				end,
				equip = function()
					return WideButton({
						Text = "Equip",
						Size = UDim2.fromScale(1, 1),
						ScaleLayout = true,
						Color = Color3.fromRGB(99, 255, 0),
						TextureTransparency = 0.72,
						OnActivated = props.OnEquip,
					})
				end,
				equipped = function()
					return WideButton({
						Text = "Equipped",
						Size = UDim2.fromScale(1, 1),
						ScaleLayout = true,
						Color = Color3.fromRGB(99, 255, 0),
						DisabledColor = Color3.fromRGB(99, 255, 0),
						TextureTransparency = 0.72,
						Disabled = true,
					})
				end,
			}),
		}),
		table.unpack(Surface({
			Radius = UDim.new(0, 0),
			Texture = "rbxassetid://137638295200351",
			TileSize = UDim2.fromScale(0.2, 0.3),
			TextureTransparency = 0.63,
			Highlight = 0,
			Shadow = 0,
		})),
	})
end

return OPSwordCard
