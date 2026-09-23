local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring

local asset = Format.asset -- "123" / "rbxassetid://123" / "" -> корректный uri

--[[
	CloseButton — квадратный крестик закрытия для полоски тайтла экрана.

	По умолчанию — красноватый квадрат со скруглением и чёрной обводкой,
	по центру символ «✕». Можно задать свою иконку через Icon. Лёгкая
	просадка масштаба при наведении/нажатии.
]]

export type Props = {
	ScaleLayout: boolean?,
	OnActivated: (() -> ())?,

	Icon: string?, -- картинка вместо «✕» ("rbxassetid://..." или голый id)
	IconInset: number?, -- отступ иконки/символа от краёв кнопки (по умолч. 4)

	Size: UDim2?, -- по умолч. квадрат 32x32
	LayoutOrder: number?,
	AnchorPoint: Vector2?,
	Position: UDim2?,
	ZIndex: number?,
	CornerRadius: UDim?,

	Color: Color3?, -- фон
	IconColor: Color3?, -- цвет «✕» / тонировка иконки

	StrokeColor: Color3?,
	StrokeThickness: number?,
	StrokeTransparency: number?,
}

local function CloseButton(props: Props)
	local size = props.Size or UDim2.fromOffset(32, 32)
	local radius = props.CornerRadius or (if props.ScaleLayout then UDim.new(0.06, 0) else UDim.new(0, 6))
	local color = props.Color or Color3.fromRGB(238, 52, 52)
	local iconColor = props.IconColor or Color3.fromRGB(245, 240, 240)

	local inset = props.IconInset or 4
	local hasIcon = props.Icon ~= nil and props.Icon ~= ""

	local hovered = source(false)
	local pressed = source(false)
	local scale = spring(function()
		if pressed() then
			return 0.9
		end
		return hovered() and 1.08 or 1
	end, 0.16)

	return create("ImageButton")({
		Name = "CloseButton",
		Size = size,
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		ZIndex = props.ZIndex,
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		ImageTransparency = 1,

		create("UICorner")({ CornerRadius = radius }),
		create("UIScale")({ Scale = scale }),
		create("UIStroke")({
			Thickness = props.StrokeThickness or 1.5,
			Color = props.StrokeColor or Color3.new(0, 0, 0),
			Transparency = props.StrokeTransparency or 0.1,
		}),
		-- лёгкий вертикальный градиент для объёма
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.12), color:Lerp(Color3.new(0, 0, 0), 0.25)),
		}),

		-- символ «✕» (если не задана Icon)
		create("TextLabel")({
			Name = "X",
			Visible = not hasIcon,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			Text = "✕",
			TextColor3 = iconColor,
			TextScaled = true,

			create("UIPadding")({
				PaddingTop = (if props.ScaleLayout then UDim.new(0.1, 0) else UDim.new(0, inset)),
				PaddingBottom = (if props.ScaleLayout then UDim.new(0.1, 0) else UDim.new(0, inset)),
				PaddingLeft = (if props.ScaleLayout then UDim.new(0.1, 0) else UDim.new(0, inset)),
				PaddingRight = (if props.ScaleLayout then UDim.new(0.1, 0) else UDim.new(0, inset)),
			}),
			create("UIStroke")({
				Thickness = 2,
				Color = Color3.new(0, 0, 0),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),
		-- своя иконка
		create("ImageLabel")({
			Name = "Icon",
			Visible = hasIcon,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = (if props.ScaleLayout then UDim2.fromScale(0.8, 0.8) else UDim2.new(1, -inset * 2, 1, -inset * 2)),
			Image = asset(props.Icon),
			ImageColor3 = props.IconColor, -- тонировка только если задана явно (для одноцветных PNG)
			ScaleType = Enum.ScaleType.Fit, -- без искажений пропорций
		}),

		MouseButton1Down = function()
			pressed(true)
		end,
		MouseButton1Up = function()
			pressed(false)
		end,
		MouseEnter = function()
			hovered(true)
			sfx.play("HoverUI")
		end,
		MouseLeave = function()
			hovered(false)
			pressed(false)
		end,
		Activated = function()
			if props.OnActivated then
				sfx.play("ClickUI")
				props.OnActivated()
			end
		end,
	})
end

return CloseButton
