local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format) -- Format.short через EtNum

local create = vide.create
local spring = vide.spring
local read = vide.read -- read(x): вернёт x() если это функция-источник, иначе x

export type Numeric = number | string | () -> number | string

export type Props = {
	Icon: string?, -- картинка слева (например бицепс), "rbxassetid://..."
	Level: Numeric,
	Current: Numeric, -- опыт в текущем уровне (для текста "cur / req")
	Required: Numeric, -- нужно для следующего уровня (для текста)
	Total: Numeric, -- общее число (сила) под полоской
	Progress: (number | () -> number)?, -- заполнение 0..1 напрямую;
	--                                      если не задано — считается Current/Required

	Large: boolean?,
	LayoutOrder: number?,
	CornerRadius: UDim?,
	AnimationSpeed: number?, -- period для spring: меньше = быстрее (по умолч. 0.35)

	-- ЦВЕТА
	FillColor: Color3?,
	FillColor2: Color3?, -- если задан — вертикальный градиент на заливке
	TrackColor: Color3?,
	TextColor: Color3?,

	-- ОБВОДКА (у полосы и у заполнения)
	StrokeColor: Color3?, -- по умолч. чёрный
	StrokeThickness: number?, -- по умолч. 1.5
	StrokeTransparency: number?, -- по умолч. 0.15

	-- ТЕКСТУРЫ (всё опционально, просто загруженная картинка "rbxassetid://..." или голый id).
	-- Накладываются поверх соответствующего слоя.
	TrackImage: string?, -- на пустой (фоновой) части полосы
	FillImage: string?, -- на заполняющей части
	GlossImage: string?, -- верхний слой: блик стекла / объём
	TextureTransparency: number?, -- прозрачность Track/Fill текстур (по умолч. 0.05)
	TextureColor: Color3?, -- тонировка текстур (ImageColor3), для серых/белых PNG с alpha
	TextureScaleType: Enum.ScaleType?, -- по умолч. Tile (повтор без искажений); Stretch — растянуть одну
	TextureTileSize: UDim2?, -- размер плитки при Tile (по умолч. = высота полосы; меньше = мельче узор)

	-- ПОДЛОЖКА под числом общей силы (полоска, размытая с двух сторон)
	TotalColor: Color3?,
	TotalImage: string?, -- текстура на подложку
	TotalFade: number?, -- 0..0.5: сколько с каждого края уходит в прозрачность (по умолч. 0.4)
}

local asset = Format.asset -- "123" / "rbxassetid://123" / "" -> корректный uri

local function XpBar(props: Props)
	local large = props.Large
	local barH = large and 40 or 28
	local pad = large and 8 or 6
	local iconSize = barH - pad * 2
	local textSize = large and 18 or 14
	local radius = props.CornerRadius or UDim.new(0, 1)

	local fillColor = props.FillColor or Color3.fromRGB(250, 175, 35) -- жёлтый с тёплым оттенком (основной)
	local fillColor2 = props.FillColor2 or Color3.fromRGB(255, 210, 80) -- яркий жёлтый (верх градиента)
	local trackColor = props.TrackColor or Color3.fromRGB(20, 20, 24)
	local textColor = props.TextColor or Color3.fromRGB(240, 245, 240)
	local totalColor = props.TotalColor or Color3.fromRGB(15, 15, 18)
	local totalFade = math.clamp(props.TotalFade or 0.4, 0, 0.5)

	local texTransparency = props.TextureTransparency or 0.55
	local texColor = props.TextureColor or Color3.new(1, 1, 1)
	-- Tile сохраняет пропорции картинки и повторяет её; Stretch растянул бы и исказил
	local texScaleType = props.TextureScaleType or Enum.ScaleType.Tile
	local texTileSize = props.TextureTileSize or UDim2.fromOffset(barH, barH) -- квадратная плитка = высота полосы
	local totalTextSize = large and 22 or 16
	local totalH = totalTextSize + pad

	-- прогресс 0..1 + плавная анимация заполнения
	local function progress(): number
		if props.Progress ~= nil then
			return math.clamp(tonumber(read(props.Progress)) or 0, 0, 1)
		end
		-- запасной вариант: если Current/Required — простые числа
		local cur = tonumber(read(props.Current)) or 0
		local req = math.max(tonumber(read(props.Required)) or 1, 1)
		return math.clamp(cur / req, 0, 1)
	end
	local fillAlpha = spring(progress, props.AnimationSpeed or 0.35)

	local function textStroke(thickness: number?)
		return create("UIStroke")({
			Thickness = thickness or 1.5,
			Color = Color3.new(0, 0, 0),
			Transparency = 0.1,
		})
	end

	-- обводка для полосы и для заполнения (одинаковый стиль)
	local function barStroke()
		return create("UIStroke")({
			Thickness = props.StrokeThickness or 1.5,
			Color = props.StrokeColor or Color3.new(0, 0, 0),
			Transparency = props.StrokeTransparency or 0.15,
		})
	end

	return create("Frame")({
		Name = "XpBar",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			-- Bar тянется на всю ширину (центрирование ему безразлично),
			-- Total авто-ширины => встаёт по центру под полосой
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),

		--======================================================================
		-- САМА ПОЛОСА (стопка слоёв, старший слой = выше по ZIndex)
		--======================================================================
		create("Frame")({
			Name = "Bar",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, barH),
			BackgroundColor3 = trackColor,
			BackgroundTransparency = 0.7, -- «слегка прозрачный» фон-пустота
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = radius }),
			barStroke(),

			----- СЛОЙ 1: текстура на пустой части --------------------------------
			create("ImageLabel")({
				Name = "TrackTexture",
				ZIndex = 1,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = asset(props.TrackImage), -- нет id -> ничего не рисуется
				ImageTransparency = texTransparency,
				ImageColor3 = texColor,
				ScaleType = texScaleType,
				TileSize = texTileSize,
			}),

			----- СЛОЙ 2: заполнение (ширина = прогресс, анимируется spring) -------
			create("Frame")({
				Name = "Fill",
				ZIndex = 2,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = function()
					return UDim2.new(fillAlpha(), 0, 1, 0)
				end,
				BackgroundColor3 = fillColor,
				ClipsDescendants = true,

				create("UICorner")({ CornerRadius = radius }),
				barStroke(), -- обводка заполнения (правый край = ведущая кромка прогресса)
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(fillColor2, fillColor), -- одинаковые цвета => no-op
				}),
				create("ImageLabel")({
					Name = "FillTexture",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = asset(props.FillImage),
					ImageTransparency = texTransparency,
					ImageColor3 = texColor,
					ScaleType = texScaleType,
					TileSize = texTileSize,
				}),
			}),

			----- СЛОЙ 3: содержимое (иконка, Level N, cur/req) -------------------
			create("ImageLabel")({
				Name = "Icon",
				ZIndex = 3,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, pad, 0.5, 0),
				Size = UDim2.fromOffset(iconSize, iconSize),
				Image = asset(props.Icon),
			}),
			create("TextLabel")({
				Name = "Level",
				ZIndex = 3,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, pad + iconSize + pad, 0.5, 0),
				Size = UDim2.new(0, 0, 1, 0),
				Font = Enum.Font.GothamBold,
				TextSize = textSize,
				TextColor3 = textColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = function()
					return "Level " .. tostring(read(props.Level))
				end,

				textStroke(),
			}),
			create("TextLabel")({
				Name = "Amount",
				ZIndex = 3,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -pad, 0.5, 0),
				Size = UDim2.new(0, 0, 1, 0),
				Font = Enum.Font.GothamBold,
				TextSize = textSize,
				TextColor3 = textColor,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = function()
					return Format.short(read(props.Current)) .. " / " .. Format.short(read(props.Required))
				end,

				textStroke(),
			}),

			----- СЛОЙ 4: внешний блик / объём ----------------------------------
			create("Frame")({
				Name = "Gloss",
				ZIndex = 4,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0,

				create("UICorner")({ CornerRadius = radius }),
				-- лёгкий блик у верхнего края (работает и без текстуры)
				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.78),
						NumberSequenceKeypoint.new(0.35, 1),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
				-- своя текстура блика поверх (например картинка стеклянного блика)
				create("ImageLabel")({
					Name = "GlossTexture",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = asset(props.GlossImage),
					ScaleType = Enum.ScaleType.Stretch,
				}),
			}),
		}),

		--======================================================================
		-- ОБЩАЯ СИЛА: "<число> Magnetism" на подложке, размытой с двух сторон.
		--
		-- Корень — ImageLabel (это и есть подложка): его фон + текстура + UIGradient
		-- сами занимают весь элемент, без дочерних Frame'ов со Scale-размером.
		-- Внутри AutomaticSize нельзя держать детей со Scale в авто-оси — иначе
		-- подложка «раздувается» на весь экран. Поэтому единственный ребёнок —
		-- TextLabel с AutomaticSize, он и задаёт размер.
		--======================================================================
		create("ImageLabel")({
			Name = "Total",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.XY, -- размер = текст + падинги ниже
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = totalColor,
			BackgroundTransparency = 0.7,
			Image = asset(props.TotalImage),
			ImageTransparency = 0.5,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(totalH, totalH),

			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			-- прозрачно по краям, плотно в центре => «размывается с двух сторон».
			-- UIGradient на ImageLabel гасит и фон, и текстуру; на текст-ребёнка
			-- НЕ распространяется.
			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(totalFade, 0),
					NumberSequenceKeypoint.new(1 - totalFade, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
			-- отступы подложки вокруг текста (маленькие — полоска почти по тексту)
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 1),
			}),

			create("TextLabel")({
				Name = "Value",
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = totalTextSize,
				TextColor3 = textColor,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Text = function()
					return Format.short(read(props.Total)) .. " Magnetism"
				end,

				textStroke(),
			}),
		}),
	})
end

return XpBar
