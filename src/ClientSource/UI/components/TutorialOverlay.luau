local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Tutorial = require(ReplicatedStorage.ClientSource.UI.tutorial)
local viewportScale = require(ReplicatedStorage.ClientSource.UI.viewportScale)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local show = vide.show
local effect = vide.effect
local clock = rarityFx.clock

--[[
	TutorialOverlay — текстовый слой туториала (отдельный ScreenGui, см. App):

	  * цель в стиле баннера «N COMBO!» (мельче, жёлтая) внизу под комбо и уведомлениями: заголовок, подпись, тонкая полоска
	    прогресса. Мягкие шаги (Tutorial.compact) меньше и бледнее;
	  * пульсирующее кольцо «кликай» на первом шаге.

	Ничего не перехватывает (нет кнопок/Active), поэтому игре не мешает. Размеры — через тот же
	глобальный масштаб интерфейса, что у HUD (viewportScale), позиции — долями экрана.
]]

local COLOR = Theme.TutorialAccent

local function wave(speed: number): number
	return math.sin(clock() * speed) * 0.5 + 0.5
end

local function message(): Tutorial.Message?
	return Tutorial.message()
end

-- Цель в стиле баннера «N COMBO!» (FeedbackOverlay.showNext), но мельче и в другом цвете (жёлтый акцент
-- туториала вместо медного комбо): без плашки, заголовок GothamBlack с вертикальным градиентом и обводкой size/12,
-- подпись GothamBlack белая, «поп» масштаба 0.3 -> 1 (Back) и покачивание заголовка -6° -> 0 (Elastic) при смене шага.
-- Стоит внизу по центру ПОД комбо и обычными уведомлениями (та же полоса, где выезжают Level Up / +Money):
-- FeedbackOverlay поднимает комбо и уведомления на Tutorial.PILL_RESERVE, пока цель показана — наложения нет.
local WHITE = Color3.new(1, 1, 1)
local ACCENT = Theme.TutorialAccent
local TITLE_SIZE = 30
local SUBTITLE_SIZE = 17
local COMPACT_SCALE = 0.8 -- мягкие шаги тише, но тот же стиль

local function bannerStroke(textSize: number)
	return create("UIStroke")({
		Thickness = math.max(textSize / 12, 2),
		Color = Color3.new(0, 0, 0),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

local function Pill()
	local scale = create("UIScale")({ Scale = 0.3 }) :: UIScale

	local title = create("TextLabel")({
		Name = "Title",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TITLE_SIZE + 4), -- одна строка: длинный заголовок ужимается, а не переносится
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextSize = TITLE_SIZE,
		TextColor3 = ACCENT,
		TextTransparency = function()
			return if Tutorial.compact() then 0.3 else 0
		end,
		Text = function()
			local m = message()
			return m and m.Title or ""
		end,
		bannerStroke(TITLE_SIZE),
		create("UITextSizeConstraint")({ MaxTextSize = TITLE_SIZE }),
		create("UIGradient")({
			Color = ColorSequence.new(WHITE:Lerp(ACCENT, 0.4), ACCENT),
			Rotation = 90,
		}),
	}) :: TextLabel

	-- «поп» при появлении и смене шага; мягкие шаги сразу меньше
	local lastTitle: string? = nil
	effect(function()
		local m = message()
		local newTitle = m and m.Title
		local target = if Tutorial.compact() then COMPACT_SCALE else 1
		if newTitle and newTitle ~= lastTitle then
			lastTitle = newTitle
			scale.Scale = 0.3
			title.Rotation = -6
			TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Rotation = 0,
			}):Play()
		end
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = target,
		}):Play()
	end)

	return create("Frame")({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Tutorial.PILL_BOTTOM),
		Size = UDim2.fromScale(0.9, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		create("UISizeConstraint")({ MaxSize = Vector2.new(640, math.huge) }),
		scale,
		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 2),
		}),

		title,

		create("TextLabel")({
			Name = "Subtitle",
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, SUBTITLE_SIZE + 3),
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextSize = SUBTITLE_SIZE,
			TextColor3 = WHITE,
			TextTransparency = function()
				return if Tutorial.compact() then 0.3 else 0
			end,
			Visible = function()
				local m = message()
				return m ~= nil and m.Subtitle ~= nil
			end,
			Text = function()
				local m = message()
				return m and m.Subtitle or ""
			end,
			bannerStroke(SUBTITLE_SIZE),
			create("UITextSizeConstraint")({ MaxTextSize = SUBTITLE_SIZE }),
		}),

		show(function()
			local m = message()
			return m ~= nil and m.Progress ~= nil
		end, function()
			return create("Frame")({
				Name = "Progress",
				LayoutOrder = 3,
				Size = UDim2.fromOffset(160, 6),
				BackgroundColor3 = Theme.Steel900,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				create("Frame")({
					Name = "Fill",
					BorderSizePixel = 0,
					Size = function()
						local m = message()
						return UDim2.fromScale(m and m.Progress or 0, 1)
					end,
					BackgroundColor3 = ACCENT,

					create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				}),
			})
		end),
	})
end

-- Пульсирующее кольцо в нижней половине экрана: «жми сюда (куда угодно)».
local function TapHint()
	return create("Frame")({
		Name = "TapHint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.64, 0.62),
		Size = function()
			return UDim2.fromOffset(70 + wave(5) * 24, 70 + wave(5) * 24)
		end,
		BackgroundTransparency = 1,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		create("UIStroke")({
			Thickness = 5,
			Color = COLOR,
			Transparency = function()
				return 0.1 + wave(5) * 0.6
			end,
		}),
		create("Frame")({
			Name = "Core",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.28, 0.28),
			BackgroundColor3 = COLOR,
			BackgroundTransparency = function()
				return 0.2 + wave(5) * 0.4
			end,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
		}),
	})
end

local function TutorialOverlay()
	local guiScale = viewportScale()

	return create("Frame")({
		Name = "Tutorial",
		BackgroundTransparency = 1,
		Size = function()
			local s = guiScale()
			return UDim2.fromScale(1 / s, 1 / s)
		end,

		create("UIScale")({ Scale = guiScale }),

		show(function()
			return Tutorial.active() and message() ~= nil
		end, Pill),
		show(Tutorial.tapHint, TapHint),
	})
end

return TutorialOverlay
