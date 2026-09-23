local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring
local read = vide.read -- read(x): x() если это источник, иначе x

local asset = Format.asset

-- Общая тайловая текстура проекта (та же, что на прогресс-баре и пилюлях).
local DEFAULT_TEXTURE = "137638295200351"

--[[
	WideButton — широкая кнопка-пилюля только с текстом (Rebirth / Skip и т.п.).

	Фон — вертикальный градиент (верх светлее, низ темнее) поверх базового цвета,
	чёрная обводка. Текст — отдельным слоем (градиент фона его не задевает), с
	собственной обводкой. Наведение/нажатие дают лёгкий отклик масштаба через
	spring. Disabled гасит цвет и блокирует клик.
]]

export type Props = {
	ScaleLayout: boolean?,
	Text: string | () -> string,
	OnActivated: (() -> ())?,

	Size: UDim2?, -- по умолч. 200x60
	LayoutOrder: number?,
	CornerRadius: UDim?,
	TextSize: number?, -- по умолч. 28

	Color: Color3?, -- базовый цвет фона (середина градиента)
	DisabledColor: Color3?, -- цвет фона в состоянии Disabled (по умолч. серый)
	DisabledTextTransparency: number?, -- прозрачность текста в Disabled (по умолч. 0.4); 0 — держать текст полностью белым (напр. "Owned"/"Equipped")
	TextColor: Color3?,

	Texture: string?, -- тайловая текстура поверх фона (по умолч. общая проекта; "" — без текстуры)
	TextureTransparency: number?, -- по умолч. 0.82

	Disabled: (boolean | () -> boolean)?,
}

local function WideButton(props: Props)
	local size = props.Size or UDim2.fromOffset(200, 60)
	local radius = props.CornerRadius or (if props.ScaleLayout then UDim.new(0.025, 0) else UDim.new(0, 4))
	local textSize = props.TextSize or 28

	local color = props.Color or Color3.fromRGB(226, 62, 72)
	local disabledColor = props.DisabledColor or Color3.fromRGB(108, 108, 112)
	local disabledTextTransparency = props.DisabledTextTransparency or 0.4
	local textColor = props.TextColor or Color3.fromRGB(245, 245, 240)

	local texture = if props.Texture ~= nil then props.Texture else DEFAULT_TEXTURE
	local texTransparency = props.TextureTransparency or 0.68
	local tile = math.max(size.Y.Offset, 32)

	local function disabled(): boolean
		return read(props.Disabled) == true
	end

	local pressed = source(false)
	local hovered = source(false)
	local scale = spring(function()
		if disabled() then
			return 1
		end
		if pressed() then
			return 0.96
		end
		return hovered() and 1.04 or 1
	end, 0.16)

	return create("TextButton")({
		Name = "WideButton",
		Size = size,
		LayoutOrder = props.LayoutOrder,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = function()
			return disabled() and disabledColor or color
		end,
		BackgroundTransparency = function()
			return disabled() and 0.15 or 0
		end,
		Active = function()
			return not disabled()
		end,

		create("UICorner")({ CornerRadius = radius }),
		create("UIScale")({ Scale = scale }),
		-- градиент умножает цвет фона: держим верх на чистом цвете (сочно), к низу
		-- лишь лёгкая тень для объёма
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
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		create("ImageLabel")({
			Name = "Texture",
			Visible = texture ~= "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = asset(texture),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = if props.ScaleLayout then UDim2.fromScale(0.14, 0.4) else UDim2.fromOffset(tile, tile),
			ImageTransparency = function()
				return disabled() and math.min(texTransparency + 0.25, 1) or texTransparency
			end,

			create("UICorner")({ CornerRadius = radius }),
		}),

		create("TextLabel")({
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			Text = props.Text,
			TextSize = textSize,
			TextScaled = props.ScaleLayout == true,
			TextColor3 = textColor,
			TextTransparency = function()
				return disabled() and disabledTextTransparency or 0
			end,

			create("UIStroke")({
				Thickness = 2,
				Color = Color3.new(0, 0, 0),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),

		-- отделка кромок: светлая линия по верху и бокам (гаснет к низу) + тёмная
		-- полоска снизу — тот же приём, что на полоске тайтла у Panel
		EdgeAccent({ Radius = radius, ScaleLayout = props.ScaleLayout }),

		MouseButton1Down = function()
			if not disabled() then
				pressed(true)
			end
		end,
		MouseButton1Up = function()
			pressed(false)
		end,
		MouseEnter = function()
			if not disabled() then
				hovered(true)
				sfx.play("HoverUI")
			end
		end,
		MouseLeave = function()
			pressed(false)
			hovered(false)
		end,
		Activated = function()
			if not disabled() and props.OnActivated then
				sfx.play("ClickUI")
				props.OnActivated()
			end
		end,
	})
end

return WideButton
