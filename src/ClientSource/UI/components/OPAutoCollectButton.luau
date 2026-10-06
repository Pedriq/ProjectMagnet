local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local source = vide.source
local spring = vide.spring
local clock = rarityFx.clock

local asset = Format.asset

--[[
	OPAutoCollectButton — премиум-кнопка «OP Auto Collect» в колонке донат-кнопок HUD
	(BuffButtons, самая верхняя). ПОКА ТОЛЬКО ВИЗУАЛ: покупки и логики нет.

	Стиль — глянцевая пластиковая кнопка: радужный градиент плавно перетекает
	по кругу оттенков, сверху глянцевая полоса, раз в несколько секунд проезжает мягкий
	блик, при наведении кнопка чуть подрастает. Форма и пропорции — как у BuffBuyButton (скругление 0.2, цена сверху); всё обрезано
	по скруглению (CanvasGroup).

	Геометрия — только доли (как BuffBuyButton): высота — HeightScale от высоты родителя.
]]

export type Props = {
	LayoutOrder: number?,
	HeightScale: number?, -- доля высоты родителя под весь блок (цена + кнопка), по умолч. 0.17
	OnActivated: (() -> ())?, -- пока не используется
}

local WHITE = Color3.new(1, 1, 1)
local TEST_PRICE = 199 -- ВРЕМЕННО: тестовая цена в Robux, пока нет продукта
local TEXTURE = "119993804734501"
local RAINBOW_STEPS = 8 -- ключевых точек на круг оттенков (ColorSequence: максимум 20)

-- Радужный градиент: оттенок идёт по кругу, фаза сдвигается со временем. Первая и последняя
-- точки имеют один и тот же оттенок (t и t+1), поэтому цикл бесшовный. Фаза вычитается — цвета бегут слева направо.
local function rainbowSequence(value: number): ColorSequence
	local phase = (clock() * 0.14) % 1
	local keys = {}
	for i = 0, RAINBOW_STEPS do
		local t = i / RAINBOW_STEPS
		keys[i + 1] = ColorSequenceKeypoint.new(t, Color3.fromHSV((t - phase) % 1, 1, value))
	end
	return ColorSequence.new(keys)
end

local function rainbow(): ColorSequence
	return rainbowSequence(1)
end

local function OPAutoCollectButton(props: Props)
	local heightScale = props.HeightScale or 0.17

	local pressed = source(false)
	local hovered = source(false)
	local scale = spring(function()
		if pressed() then
			return 0.96
		end
		return hovered() and 1.04 or 1
	end, 0.16)

	return create("Frame")({
		Name = "OPAutoCollectButton",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(1, heightScale),
		BackgroundTransparency = 1,

		-- цена над кнопкой, как у BuffBuyButton ("<R$>N", зелёным)
		create("TextLabel")({
			Name = "PriceLabel",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(1, 0.3),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextColor3 = WHITE, -- цвет задаёт радужный UIGradient ниже
			Text = `\u{E002}{TEST_PRICE}`,
			TextScaled = true,

			create("UIStroke")({ Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.1 }),
			-- те же перетекающие цвета, что у кнопки
			create("UIGradient")({ Rotation = 0, Color = rainbow }),
		}),

		create("TextButton")({
			Name = "Button",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 0.66),
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",

			create("UIScale")({ Scale = scale }),

			-- Тело-«таблетка» в CanvasGroup: он обрезает содержимое по скруглению
			-- (ClipsDescendants у обычных Frame скругления не учитывает — отсюда были
			-- квадратные углы). Рамки нет вообще.
			create("CanvasGroup")({
				Name = "Body",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(0.2, 0) }),
				-- тонкая обводка как у остальных кнопок: следует скруглению, не прямоугольная
				create("UIStroke")({ Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.05 }),

				create("Frame")({
					Name = "Rainbow",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = WHITE,
					BorderSizePixel = 0,

					create("UIGradient")({
						Rotation = 0,
						Color = rainbow,
					}),
				}),

				create("ImageLabel")({
					Name = "Texture",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = asset(TEXTURE),
					ImageTransparency = 0.75,
					ScaleType = Enum.ScaleType.Tile,
					TileSize = UDim2.fromScale(0.14, 0.4),
				}),

				-- глянцевая полоса вдоль верхней кромки
				create("Frame")({
					Name = "Gloss",
					Position = UDim2.fromScale(0.1, 0.08),
					Size = UDim2.fromScale(0.8, 0.22),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.65,
					BorderSizePixel = 0,

					create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				}),

				-- мягкий блик, проезжающий слева направо; большую часть времени за кадром
				create("Frame")({
					Name = "Shimmer",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromScale(0.22, 2.2),
					Rotation = 20,
					BorderSizePixel = 0,
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.6,
					Position = function()
						local p = (clock() * 0.22) % 1
						return UDim2.fromScale(-0.4 + p * 1.8, 0.5)
					end,

					create("UIGradient")({
						Rotation = 0,
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.5, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
					}),
				}),
			}),

			create("TextLabel")({
				Name = "Title",
				ZIndex = 4,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.82, 0.62),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Text = "OP Auto Collect",
				TextScaled = true,
				TextWrapped = true,
				TextColor3 = WHITE,

				create("UIStroke")({
					Thickness = 1.5,
					Color = Color3.new(0, 0, 0),
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			}),

			MouseButton1Down = function()
				pressed(true)
			end,
			MouseButton1Up = function()
				pressed(false)
			end,
			MouseEnter = function()
				hovered(true)
			end,
			MouseLeave = function()
				pressed(false)
				hovered(false)
			end,
		}),
	})
end

return OPAutoCollectButton
