local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring

local asset = Format.asset

--[[
	PowerBuyButton — кнопка докупки силы за Robux (пока без функционала).

	В отличие от ActionButton у неё НЕТ квадратной подложки: кликабельная область —
	сама картинка (ImageButton, фон прозрачный). Под картинкой — подпись бонуса
	("+100k" и т.п.), сверху-справа поверх картинки — бейдж цены робуксами.

	Корень — прозрачный Frame ("Slot") на всю выделенную под элемент долю
	PowerColumn; внутри нег — и картинка, и подпись под ней, ОБЕ внутри границ
	Slot. Раньше подпись торчала ниже границ самой ImageButton (это и был сам
	клик-элемент), из-за чего UIListLayout родителя не резервировал под неё
	место и подписи соседних кнопок наезжали на иконку следующей — теперь вся
	видимая высота (иконка + текст) учтена в Size одного элемента.
]]

export type Props = {
	Icon: string, -- rbxassetid картинки-кнопки
	Text: string, -- подпись под картинкой, напр. "+100k"
	Price: number, -- цена в Robux для бейджа

	HeightScale: number?, -- доля высоты родителя под весь слот (иконка + подпись), по умолч. 0.3267 (3 слота + 2 паддинга по 0.01 = вся высота PowerColumn)
	-- доля слота под саму картинку. Слот у иконки широкий и невысокий (доля от
	-- ширины экрана по X, но от высоты узкой колонки по Y), поэтому чтобы
	-- картинка (ScaleType.Fit, квадратный ассет) реально заполняла бокс, а не
	-- сжималась в середину с пустыми полями по бокам (из-за чего бейдж цены
	-- у угла бокса выглядел далеко от видимой картинки) — X-доля здесь заметно
	-- меньше Y-доли. По умолч. 33% ширины / 78% высоты слота (остальное —
	-- подписи "+100k" снизу, ей отдано больше места, чтобы цифры не были мелкими).
	IconScale: UDim2?,
	LayoutOrder: number?,
	OnActivated: (() -> ())?,
}

local function PowerBuyButton(props: Props)
	local heightScale = props.HeightScale or 0.3267
	local iconScale = props.IconScale or UDim2.fromScale(0.33, 0.78)

	local pressed = source(false)
	local hovered = source(false)
	local scale = spring(function()
		if pressed() then
			return 0.94
		end
		return hovered() and 1.06 or 1
	end, 0.18)

	return create("Frame")({
		Name = "PowerBuyButtonSlot",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(1, heightScale),
		BackgroundTransparency = 1,

		create("ImageButton")({
			Name = "PowerBuyButton",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = iconScale,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = asset(props.Icon),
			ScaleType = Enum.ScaleType.Fit,

			create("UIScale")({ Scale = scale }),

			-- бейдж цены — сверху-справа поверх картинки
			create("TextLabel")({
				Name = "PriceBadge",
				ZIndex = 2,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0.6, 0, 0.32, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Text = `\u{E002}{props.Price}`,
				TextScaled = true,
				TextColor3 = Color3.fromRGB(70, 220, 90),

				create("UIStroke")({
					Thickness = 1,
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

		-- подпись бонуса — под картинкой, внутри границ Slot
		create("TextLabel")({
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(1, 0.22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = props.Text,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),

			create("UIStroke")({
				Thickness = 1.2,
				Color = Color3.new(0, 0, 0),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),
	})
end

return PowerBuyButton
