local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring
local read = vide.read -- read(x): x() если это источник/функция, иначе x

local asset = Format.asset

--[[
	BuffBuyButton — широкая кнопка покупки постоянного множителя для HUD (см.
	HUD.luau — там Title/Price/OnActivated привязаны к следующей непройденной
	ступени PermanentMultiplierConfig, а сама кнопка скрывается через show(),
	когда все ступени куплены).

	Вся геометрия — только доли (UDim2.fromScale), без единого пиксельного офсета
	и без AutomaticSize: высота кнопки и цены над ней — фиксированные проценты
	от высоты родителя (BuffButtons в HUD, у неё самой тоже нет AutomaticSize —
	см. коммент там). Так весь блок предсказуемо держит свою долю экрана на
	любом разрешении, вместо того чтобы зависеть от текста/аспекта картинки.

	Стиль: цветной фон (жёлто-оранжевый для Strength, зелёный для Money), крупная
	иконка по центру — специально БОЛЬШЕ высоты кнопки по Y, обрезается кнопкой
	(ClipsDescendants), поэтому не вылезает за верхнюю/нижнюю кромку. Снизу —
	тёмная полоска на всю ширину с названием ("x2 Strength" / "x2 Money"). Сверху,
	уже вне кнопки — цена зелёным текстом с иконкой робуксов ("Only <R$>3").
]]

local GREEN_PRICE_COLOR = Color3.fromRGB(95, 247, 95)

-- Общая тайловая текстура проекта (та же, что на WideButton/XpBar).
local DEFAULT_TEXTURE = "137638295200351"

local COLORS = {
	Strength = { Color = Color3.fromRGB(255, 158, 25), Light = Color3.fromRGB(255, 214, 130) },
	Money = { Color = Color3.fromRGB(48, 199, 60), Light = Color3.fromRGB(170, 255, 150) },
}

export type Props = {
	Type: "Strength" | "Money",
	Title: string | (() -> string), -- "x2 Strength" / "x2 Money" (реактивно — следующая ступень)
	Icon: string, -- rbxassetid картинки силы/денег
	Price: (number | (() -> number))?, -- по умолч. 3 (Robux), реактивно — следующая ступень

	HeightScale: number?, -- доля высоты родителя под весь блок, по умолч. 0.2
	LayoutOrder: number?,
	OnActivated: (() -> ())?,
}

local function BuffBuyButton(props: Props)
	local heightScale = props.HeightScale or 0.2
	local palette = COLORS[props.Type] or COLORS.Strength

	local pressed = source(false)
	local hovered = source(false)
	local scale = spring(function()
		if pressed() then
			return 0.96
		end
		return hovered() and 1.03 or 1
	end, 0.16)

	return create("Frame")({
		Name = `BuffBuyButton_{props.Type}`,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(1, heightScale),
		BackgroundTransparency = 1,

		-- === "Only <R$>Price", зелёным, над кнопкой ===
		create("TextLabel")({
			Name = "PriceLabel",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, 0.3),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextColor3 = GREEN_PRICE_COLOR,
			Text = function()
				return `Only \u{E002}{read(props.Price) or 3}`
			end,
			TextScaled = true,

			create("UIStroke")({ Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.1 }),
		}),

		-- === сама кнопка ===
		create("TextButton")({
			Name = "Button",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 0.66),
			AutoButtonColor = false,
			ClipsDescendants = true,
			Text = "",
			BackgroundColor3 = palette.Color,

			create("UICorner")({ CornerRadius = UDim.new(0.2, 0) }),
			create("UIScale")({ Scale = scale }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(palette.Light, palette.Color),
			}),
			create("UIStroke")({
				Thickness = 1,
				Color = Color3.new(0, 0, 0),
				Transparency = 0.05,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),

			create("ImageLabel")({
				Name = "Texture",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = asset(DEFAULT_TEXTURE),
				ImageTransparency = 0.45,
				-- Tile вместо Stretch — иначе на широкой/невысокой кнопке узор
				-- растягивается. X/Y-доли TileSize НЕ равны (0.12/0.4) специально:
				-- Button — широкий и невысокий (аспект ~3.34:1 при типичном экране),
				-- а TileSize.X считается от ширины, TileSize.Y — от высоты объекта,
				-- так что для КВАДРАТНОЙ плитки в пикселях доли обязаны быть в
				-- обратной аспекту пропорции (0.12*width ≈ 0.4*height). Одинаковые
				-- доли (как у WideButton, но там другой аспект) давали плитку
				-- шире, чем выше — визуально "растянутый" узор.
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromScale(0.12, 0.4),

				create("UICorner")({ CornerRadius = UDim.new(0.2, 0) }),
			}),

			-- иконка сильно больше высоты кнопки — центр перекрывает верх/низ,
			-- но ClipsDescendants у кнопки обрезает всё, что торчит наружу
			create("ImageLabel")({
				Name = "Icon",
				ZIndex = 1,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.44),
				Size = UDim2.fromScale(0.88, 1.55),
				Image = asset(props.Icon),
				ScaleType = Enum.ScaleType.Fit,
			}),

			-- лёгкая тёмная подложка только у нижней половины (градиент — сверху
			-- прозрачная, снизу лишь слегка затемняет) — верх кнопки с иконкой
			-- остаётся чистым/светлым, не "грязным"
			create("Frame")({
				Name = "TitleBar",
				ZIndex = 2,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromScale(1, 0.55),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,

				-- те же АБСОЛЮТНЫЕ (в пикселях) скругления, что у кнопки:
				-- Button.CornerRadius = 0.2 от высоты Button; у TitleBar высота
				-- 0.55 * Button, значит скейл 0.2 / 0.55 = 0.3636.
				create("UICorner")({ CornerRadius = UDim.new(0.3636, 0) }),
				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0.45),
					}),
				}),
			}),

			-- подпись — отдельно от тёмной подложки, размером почти во всю
			-- кнопку (крупный текст), поверх и подложки, и иконки
			create("TextLabel")({
				Name = "Title",
				ZIndex = 3,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.94),
				Size = UDim2.fromScale(0.92, 0.78),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Text = props.Title,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),

				create("UIStroke")({
					Thickness = 1,
					Color = Color3.new(0, 0, 0),
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			}),

			-- Underline = false: полоска EdgeAccent тонкая (9% высоты Button), а
			-- скругление у Button — крупное (20% высоты); полоска физически не
			-- может скруглиться настолько же (максимум — половина своей же
			-- высоты) и торчала квадратными углами за пределы скруглённого низа
			-- кнопки. Нижнее затемнение уже даёт свой TitleBar (скругление у
			-- него подобрано под Button отдельно) — эта полоска просто лишняя.
			EdgeAccent({ Radius = UDim.new(0.2, 0), ScaleLayout = true, LightThickness = 2, Underline = false }),

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
				pressed(false)
				hovered(false)
			end,
			Activated = function()
				sfx.play("ClickUI")
				if props.OnActivated then
					props.OnActivated()
				end
			end,
		}),
	})
end

return BuffBuyButton
