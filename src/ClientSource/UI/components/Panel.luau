local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local CloseButton = require(ReplicatedStorage.ClientSource.UI.components.CloseButton)

local create = vide.create

local asset = Format.asset -- "123" / "rbxassetid://123" / "" -> корректный uri

--[[
	Panel — окно основных функций (Shop, Rebirth и т.п.).

	Композиция:
	  ┌─ TitleBar ───────────────────────────────┐   ← горизонтальная полоска
	  │ [icon]  Title …                      [✕] │     - основная текстура (TitleImage)
	  └──────────────────────────────────────────┘     - наложение поверх (TitleOverlayImage): блик/стрелка
	    ┌─ Body ──────────────────────────────┐        - иконка чуть левее названия, слегка выступает
	    │  слегка прозрачный тёмный фон       │
	    │  дети Panel уходят сюда             │      ← тело отступает от краёв тайтла на BodyInset
	    └─────────────────────────────────────┘

	У полоски тайтла, тела и крестика — обводка (общий стиль Stroke*).
	Дети (array-часть props) складываются в тело; по умолчанию туда же
	добавляется вертикальный UIListLayout — отключается через List = false.
]]

export type Props = {
	ScaleLayout: boolean?, -- Convert reference dimensions into relative sizes.
	Title: string | () -> string,
	Icon: string?, -- иконка в левой части полоски тайтла
	OnClose: (() -> ())?, -- клик по крестику
	CloseIcon: string?, -- картинка на крестике (по умолч. общая иконка «✕»)
	CloseColor: Color3?, -- фон крестика

	Size: UDim2?, -- максимальный размер окна в пикселях (по умолч. 380x460); на узких экранах ужимается
	Position: UDim2?, -- по умолч. центр родителя (0.5, 0.5)
	AnchorPoint: Vector2?, -- по умолч. (0.5, 0.5)
	ScreenMargin: number?, -- мин. отступ окна от краёв экрана, когда оно не влезает (по умолч. 16)
	LayoutOrder: number?,
	ZIndex: number?, -- по умолч. 1; подними выше затемнения/HUD при показе поверх

	-- ПОЛОСКА ТАЙТЛА
	TitleImage: string?, -- основная текстура полоски (тайловый узор)
	TitleImageScaleType: Enum.ScaleType?, -- по умолч. Tile (повтор без искажений)
	TitleImageTileSize: UDim2?, -- размер плитки при Tile (по умолч. квадрат = высота полоски)
	TitleImageTransparency: number?, -- прозрачность текстуры (по умолч. 0.3)
	TitleImageColor: Color3?, -- тонировка текстуры (ImageColor3), для серых/белых PNG
	TitleOverlayImage: string?, -- картинка поверх основной (блик, стрелка)
	TitleOverlayScaleType: Enum.ScaleType?, -- по умолч. Stretch
	TitleHighlight: boolean?, -- свет на полоске: сверху светлее (падает свет), плюс блик «волной» слева направо (по умолч. true)
	TitleUnderline: boolean?, -- тонкая тёмная полоска у низа тайтла отдельным фреймом, для объёма (по умолч. true)
	TitleShine: boolean?, -- две диагональные полоски-блика справа (толстая + тонкая), отдельными фреймами (по умолч. true)
	TitleCornerRadius: UDim?, -- скругление именно полоски тайтла (по умолч. 4, слабое)
	TitleHeight: number?, -- по умолч. 46
	TitleColor: Color3?,
	TitleTextColor: Color3?,
	TitleTextSize: number?,
	TitleTransparency: number?, -- по умолч. 0.05

	-- ТЕЛО
	BodyColor: Color3?, -- по умолч. тёмный
	BodyTransparency: number?, -- по умолч. 0.3 (слегка прозрачный)
	BodyInset: number?, -- отступ тела от краёв тайтла по горизонтали (по умолч. 12)
	BodyGap: number?, -- вертикальный зазор тело<->тайтл (по умолч. 0)
	BodyPadding: number?, -- внутренние поля тела (по умолч. 12)
	List: boolean?, -- добавить вертикальный UIListLayout в тело (по умолч. true)
	ListPadding: number?, -- шаг между детьми при List (по умолч. 8)

	CornerRadius: UDim?,

	-- ОБВОДКА (общая для тайтла, тела, крестика)
	StrokeColor: Color3?, -- по умолч. чёрный
	StrokeThickness: number?, -- по умолч. 1.5
	StrokeTransparency: number?, -- по умолч. 0.1
}

local function Panel(props: Props)
	local relative = props.ScaleLayout == true
	local function dim(xs: number, xo: number, ys: number, yo: number, height: number?): UDim2
		return if relative then UDim2.fromScale(xs + xo / 1000, ys + yo / (height or 450)) else UDim2.new(xs, xo, ys, yo)
	end
	local titleH = props.TitleHeight or 46
	local titleColor = props.TitleColor or Color3.fromRGB(46, 38, 60)
	local titleTextColor = props.TitleTextColor or Color3.fromRGB(245, 245, 240)
	local titleTextSize = props.TitleTextSize or 22
	local titleTransparency = props.TitleTransparency or 0.05
	local titleImageTransparency = math.clamp(props.TitleImageTransparency or 0.3, 0, 1)
	local titleHighlight = props.TitleHighlight ~= false
	local titleUnderline = props.TitleUnderline ~= false
	local titleShine = props.TitleShine ~= false

	local bodyColor = props.BodyColor or Color3.fromRGB(18, 15, 24)
	local bodyTransparency = math.clamp(props.BodyTransparency or 0.3, 0, 1)
	local inset = props.BodyInset or 12
	local gap = props.BodyGap or 0
	local _bodyPad = props.BodyPadding or 12
	local radius = props.CornerRadius or (if relative then UDim.new(0.01, 0) else UDim.new(0, 8))
	local titleRadius = props.TitleCornerRadius or (if relative then UDim.new(0.025, 0) else UDim.new(0, 4)) -- полоска почти не скруглена

	local iconSize = titleH + 8 -- слегка выступает за полоску

	-- Размер окна: тянется во всё доступное место минус ScreenMargin по краям,
	-- но не крупнее props.Size (в пикселях) -> на мобилке само ужимается и не уезжает.
	local screenMargin = props.ScreenMargin or 16
	local maxSize = props.Size or UDim2.fromOffset(380, 460)
	local maxW = maxSize.X.Offset > 0 and maxSize.X.Offset or 380
	local maxH = maxSize.Y.Offset > 0 and maxSize.Y.Offset or 460

	-- Тело заходит под полоску тайтла на радиус скругления -> стык без зазора.
	local overlap = math.max(radius.Offset - gap, 0)
	local bodyTop = titleH + gap - overlap

	local function stroke()
		return create("UIStroke")({
			Thickness = props.StrokeThickness or 1.5,
			Color = props.StrokeColor or Color3.new(0, 0, 0),
			Transparency = props.StrokeTransparency or 0.1,
		})
	end

	local function textStroke()
		return create("UIStroke")({
			Thickness = 2,
			Color = Color3.new(0, 0, 0),
			LineJoinMode = Enum.LineJoinMode.Round,
		})
	end

	-- одна диагональная полоска-блик: наклонённый вправо белый фрейм, концы
	-- растушёваны. Две такие (толще + тоньше) = классический глянцевый блик.
	-- centerX — доля ширины полоски (0.5 = центр); высота чуть больше полоски,
	-- лишнее срезает контейнер, так что за кромку не выезжает.
	local function titleShineBar(centerX: number, w: number, transparency: number)
		return create("Frame")({
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(centerX, 0.5),
			Size = dim(0, w, 0, titleH * 1.35, titleH),
			Rotation = 15, -- наклон вправо ("/")

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("UIGradient")({
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.32, 0.1),
					NumberSequenceKeypoint.new(0.68, 0.1),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	-- дети Panel (array-часть props) -> в тело
	local bodyChildren = {
		create("UIPadding")({
			PaddingTop = UDim.new(0.1, 0),
			PaddingBottom = UDim.new(0.01, 0),
			PaddingLeft = UDim.new(0.01, 0),
			PaddingRight = UDim.new(0.01, 0),
		}),
	}
	if props.List ~= false then
		table.insert(
			bodyChildren,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = (if relative then UDim.new(0.02, 0) else UDim.new(0, props.ListPadding or 8)),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			})
		)
	end
	for _, child in ipairs(props) do
		table.insert(bodyChildren, child)
	end

	return create("Frame")({
		Name = "Panel",
		Size = if relative then (props.Size or UDim2.fromScale(0.8, 0.75)) else UDim2.new(1, -screenMargin * 2, 1, -screenMargin * 2),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex or 1,
		BackgroundTransparency = 1,

		create("UIAspectRatioConstraint")({ AspectRatio = 1.27 }),

		-- не крупнее заданного размера; при этом не вылезает за экран (см. Size выше)
		not relative and create("UISizeConstraint")({ MaxSize = Vector2.new(maxW, maxH) }),

		--== ТЕЛО ============================================================
		-- отступ от краёв тайтла по бокам, начинается сразу под полоской
		create("Frame")({
			Name = "Body",
			AnchorPoint = Vector2.new(0, 0),
			Position = dim(0, inset, 0, bodyTop),
			Size = dim(1, -inset * 2, 1, -bodyTop),
			BackgroundColor3 = bodyColor,
			BackgroundTransparency = bodyTransparency,

			stroke(),

			table.unpack(bodyChildren),
		}),

		--== ПОЛОСКА ТАЙТЛА (стопка слоёв) ===================================
		create("Frame")({
			Name = "TitleBar",
			ZIndex = 2,
			Position = UDim2.fromScale(0, 0.065),
			Size = UDim2.fromScale(1, 0.1),
			BackgroundColor3 = titleColor,
			BackgroundTransparency = titleTransparency,
			ClipsDescendants = false,

			create("UICorner")({ CornerRadius = titleRadius }),
			stroke(),

			-- растушёвка фона полоски: сверху светлее (как будто падает свет), к низу
			-- чуть темнее — мягко, чтобы цвет тайтла оставался сочным
			create("UIGradient")({
				Name = "Shade",
				Enabled = titleHighlight,
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0.00, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.5, Color3.new(0.97, 0.97, 0.97)),
					ColorSequenceKeypoint.new(1.00, Color3.new(0.86, 0.86, 0.86)),
				}),
			}),

			-- слой 1: основная текстура
			create("ImageLabel")({
				Name = "Texture",
				ZIndex = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = asset(props.TitleImage),
				ImageTransparency = titleImageTransparency,
				ImageColor3 = props.TitleImageColor,
				ScaleType = props.TitleImageScaleType or Enum.ScaleType.Tile,
				TileSize = props.TitleImageTileSize or dim(0, titleH, 0, titleH, titleH),

				create("UICorner")({ CornerRadius = titleRadius }),
			}),
			-- слой 2: наложение поверх (блик, стрелка)
			create("ImageLabel")({
				Name = "Overlay",
				ZIndex = 2,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = asset(props.TitleOverlayImage),
				ScaleType = props.TitleOverlayScaleType or Enum.ScaleType.Stretch,

				create("UICorner")({ CornerRadius = titleRadius }),
			}),
			-- слой 2: белый блик — идёт «волной» слева направо (Rotation = 0)
			create("Frame")({
				Name = "Highlight",
				ZIndex = 2,
				Visible = titleHighlight,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromScale(1, 1),

				create("UICorner")({ CornerRadius = titleRadius }),
				create("UIGradient")({
					Rotation = 0,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0.00, 0.8),
						NumberSequenceKeypoint.new(0.18, 0.55),
						NumberSequenceKeypoint.new(0.40, 0.9),
						NumberSequenceKeypoint.new(0.62, 0.62),
						NumberSequenceKeypoint.new(0.84, 0.92),
						NumberSequenceKeypoint.new(1.00, 0.75),
					}),
				}),
			}),

			-- слой 2: диагональный блик — две полоски-фрейма (толстая + тонкая),
			-- чуть правее центра полоски. CanvasGroup вместо Frame: у повёрнутых
			-- (Rotation) детей обычный Frame.ClipsDescendants обрезает не всегда
			-- пиксель-в-пиксель — концы полосок чуть протыкали верх/низ полоски
			-- тайтла. CanvasGroup рендерит детей в офscreen-канвас и обрезает уже
			-- его — тот же приём, что у MagnetCard.lightBars (CardEffect 2).
			create("CanvasGroup")({
				Name = "Shine",
				ZIndex = 2,
				Visible = titleShine,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				GroupTransparency = 0,
				ClipsDescendants = true,

				create("UICorner")({ CornerRadius = titleRadius }),

				titleShineBar(0.65, 32, 0.73),
				titleShineBar(0.72, 15, 0.8),
			}),

			-- слой 2: тонкая тёмная полоска у нижнего края полоски — отдельный
			-- фрейм во всю ширину; тень на стыке тайтла и тела → объём
			create("Frame")({
				Name = "Underline",
				ZIndex = 2,
				Visible = titleUnderline,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = dim(1, 0, 0, 3, titleH),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = titleRadius }),
				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.86),
						NumberSequenceKeypoint.new(1, 0.55),
					}),
				}),
			}),

			-- слой 3: иконка (слева, слегка выступает), название правее иконки
			create("ImageLabel")({
				Name = "Icon",
				ZIndex = 3,
				Visible = (props.Icon ~= nil and props.Icon ~= ""),
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = dim(0, 4, 0.5, 0),
				Size = dim(0, iconSize, 0, iconSize, titleH),
				ScaleType = Enum.ScaleType.Fit,
				Image = asset(props.Icon),
			}),
			create("TextLabel")({
				Name = "Title",
				ZIndex = 3,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = dim(0, 4 + iconSize + 6, 0.5, 0),
				Size = dim(1, -(4 + iconSize + 6) - (titleH + 6), 1, 0),
				Font = Enum.Font.GothamBlack,
				TextSize = titleTextSize,
				TextScaled = relative,
				TextColor3 = titleTextColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = props.Title,

				textStroke(),
			}),

			-- слой 3: крестик справа
			CloseButton({
				ScaleLayout = relative,
				ZIndex = 3,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = dim(1, -6, 0.5, 0),
				Size = dim(0, titleH - 12, 0, titleH - 12, titleH),
				Icon = props.CloseIcon or "rbxassetid://103344771690872",
				Color = props.CloseColor,
				OnActivated = props.OnClose,
				StrokeColor = props.StrokeColor,
				StrokeThickness = props.StrokeThickness,
				StrokeTransparency = props.StrokeTransparency,
			}),
		}),
	})
end

return Panel
