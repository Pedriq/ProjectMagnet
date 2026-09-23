local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring
local read = vide.read -- read(x): x() если это источник, иначе x

--[[
	ActionButton — квадратная кнопка действия.

	Композиция (снизу вверх по ZIndex):
	  1. фон — квадрат со скруглением, слегка прозрачный, вертикальный градиент:
	     низ плотнее и темнее, вверх светлеет и «затухает» в прозрачность;
	  2. иконка по центру (чуть выше середины, чтобы низ уходил под текст);
	  3. текст у нижнего края — перекрывает нижнюю часть картинки, с чёрной обводкой.

	Весь корень — ImageButton, так что клик ловится по всей площади.
	Нажатие даёт лёгкую просадку масштаба через spring.
]]

export type Props = {
	Icon: string, -- "rbxassetid://..." или голый id
	Text: string | () -> string,
	OnActivated: (() -> ())?,

	Size: UDim2?, -- по умолч. квадрат 88x88
	LayoutOrder: number?,
	CornerRadius: UDim?,

	IconScale: number?, -- размер иконки относительно кнопки (по умолч. 0.62)
	TextSize: number?, -- по умолч. 20

	-- ЦВЕТА
	Color: Color3?, -- базовый цвет фона (середина градиента)
	TextColor: Color3?,
	BackgroundTransparency: number?, -- плотность у нижнего края (по умолч. 0.3)

	Disabled: (boolean | () -> boolean)?,

	CornerBadge: (string | () -> string)?, -- напр. "72%" в правом верхнем углу кнопки
	CornerBadgeColor: (Color3 | () -> Color3)?, -- цвет текста бейджа (по умолч. TextColor)
}

local function ActionButton(props: Props)
	local size = props.Size or UDim2.fromOffset(88, 88)
	local radius = props.CornerRadius or UDim.new(0, 8)
	local iconScale = props.IconScale or 0.62
	local textSize = props.TextSize or 20

	local color = props.Color or Color3.fromRGB(28, 24, 36)
	local textColor = props.TextColor or Color3.fromRGB(240, 245, 240)
	local bgTransparency = math.clamp(props.BackgroundTransparency or 0.3, 0, 1)

	-- верх светлее, низ темнее ("ниже слегка темнее чем сверху")
	local topColor = color:Lerp(Color3.new(1, 1, 1), 0.12)
	local bottomColor = color:Lerp(Color3.new(0, 0, 0), 0.35)

	local function disabled(): boolean
		return read(props.Disabled) == true
	end

	-- анимация нажатия/наведения
	local pressed = source(false)
	local hovered = source(false)
	local scale = spring(function()
		if pressed() then
			return 0.94
		end
		return hovered() and 1.06 or 1
	end, 0.18)

	return create("ImageButton")({
		Name = "ActionButton",
		Size = size,
		LayoutOrder = props.LayoutOrder,
		AutoButtonColor = false,
		BackgroundColor3 = color,
		-- сам фон рисует градиент; базовую прозрачность держит нижняя точка градиента
		BackgroundTransparency = bgTransparency,
		Active = function()
			return not disabled()
		end,
		ImageTransparency = 1, -- у кнопки своей картинки нет, иконка — отдельным слоем

		create("UICorner")({ CornerRadius = radius }),
		create("UIScale")({ Scale = scale }),

		-- фон: снизу плотный и тёмный -> вверх светлый и прозрачный.
		-- Rotation 90 => offset 0 сверху, 1 снизу.
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(topColor, bottomColor),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.clamp(bgTransparency + 0.45, 0, 1)), -- верх — затухает
				NumberSequenceKeypoint.new(1, 0), -- низ — как BackgroundTransparency
			}),
		}),
		create("UIStroke")({
			Thickness = 1.5,
			Color = Color3.new(0, 0, 0),
			Transparency = 0.35,
		}),

		--== СЛОЙ 2: иконка по центру, чуть выше середины ======================
		create("ImageLabel")({
			Name = "Icon",
			ZIndex = 2,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromScale(iconScale, iconScale),
			SizeConstraint = Enum.SizeConstraint.RelativeYY, -- квадрат независимо от формы кнопки
			ScaleType = Enum.ScaleType.Fit,
			Image = Format.asset(props.Icon),
			ImageTransparency = function()
				return disabled() and 0.6 or 0
			end,
		}),

		--== СЛОЙ 3: текст у нижнего края, перекрывает низ картинки ============
		create("TextLabel")({
			Name = "Label",
			ZIndex = 3,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -8, 0, textSize + 6),
			Font = Enum.Font.GothamBlack,
			TextColor3 = textColor,
			-- слово должно влезать целиком: масштабируем вниз, но не крупнее textSize
			TextScaled = true,
			TextWrapped = false,
			Text = props.Text,

			create("UITextSizeConstraint")({
				MaxTextSize = textSize,
				MinTextSize = 6,
			}),
			create("UIStroke")({
				Thickness = 2,
				Color = Color3.new(0, 0, 0),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),

		--== СЛОЙ 4: бейдж-процент в правом верхнем углу ========================
		create("TextLabel")({
			Name = "CornerBadge",
			ZIndex = 4,
			Visible = props.CornerBadge ~= nil,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(1, 0, 0.3, 0),
			Rotation = 16,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = props.CornerBadge or "",
			TextScaled = true,
			TextColor3 = props.CornerBadgeColor or textColor,
			TextXAlignment = Enum.TextXAlignment.Center,

			create("UIStroke")({
				Thickness = 1.5,
				Color = Color3.new(0, 0, 0),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),

		--== события =========================================================
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

return ActionButton
