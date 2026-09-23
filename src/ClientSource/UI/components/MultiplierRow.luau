local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)

local create = vide.create
local source = vide.source

local asset = Format.asset

--[[
	MultiplierRow — строка сравнения «сейчас -> после ребёрса»:

	  ┌────────┐      ┌────────┐
	  │ ⬛ x8.5 │  ➜   │ ⬛ x9  │
	  └────────┘      └────────┘
	   левая пилюля  стрелка  правая пилюля

	Пилюля по ширине = padding + крупная иконка + зазор + число + padding
	(AutomaticSize.X), не растягивается на всю строку. Иконка занимает почти всю
	высоту, число — чуть меньше иконки. Обе пилюли одного цвета (Color).
]]

export type Value = string | () -> string

export type Props = {
	Color: Color3, -- цвет обеих пилюль (оранжевый — сила, зелёный — деньги)
	From: Value, -- текущее значение, напр. "x8.5"
	To: Value, -- значение после ребёрса, напр. "x9"

	Icon: string?, -- иконка в пилюлях (пока не передаётся)
	IconSize: number?, -- размер иконки в px (по умолч. 52) — им же задаётся высота пилюли
	TextSize: number?, -- размер числа (по умолч. ~0.88 от иконки — чуть меньше неё)
	Padding: number?, -- поля вокруг содержимого пилюли (по умолч. 8)
	LayoutOrder: number?,
}

local function MultiplierRow(props: Props)
	local color = props.Color
	local radius = UDim.new(0, 4)

	local hasIcon = props.Icon ~= nil and props.Icon ~= ""
	local iconSize = props.IconSize or 46
	local valueTextSize = props.TextSize or math.floor(iconSize * 0.88) -- чуть меньше иконки
	local pad = props.Padding or 8
	local gap = 6 -- зазор иконка <-> число
	local pillH = iconSize + pad * 2 -- пилюля обжимает содержимое по высоте

	-- общая ширина поля под число: max по обеим пилюлям, чтобы они были одинаковыми
	local valueW = source(math.ceil(valueTextSize * 2))

	local function pill(value: Value, layoutOrder: number)
		return create("Frame")({
			Name = "Pill",
			LayoutOrder = layoutOrder,
			AutomaticSize = Enum.AutomaticSize.X, -- ширина = по содержимому; высота = pillH
			Size = UDim2.fromOffset(0, pillH),
			BackgroundColor3 = color,

			create("UICorner")({ CornerRadius = radius }),
			-- градиент умножает цвет: верх на чистом цвете (сочно), к низу лёгкая тень
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
			}),

			create("ImageLabel")({
				Name = "Texture",
				ZIndex = 0,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(pillH, pillH),
				ImageTransparency = 0.68,
				Image = asset("137638295200351"),
			}),

			-- содержимое: [pad] иконка [gap] число [pad] — оно и задаёт ширину пилюли
			create("Frame")({
				Name = "Content",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),

				create("UIPadding")({
					PaddingLeft = UDim.new(0, pad),
					PaddingRight = UDim.new(0, pad),
				}),
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, hasIcon and gap or 0),
				}),

				create("ImageLabel")({
					Name = "Icon",
					Visible = hasIcon,
					LayoutOrder = 1,
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(iconSize, iconSize),
					ScaleType = Enum.ScaleType.Fit,
					Image = asset(props.Icon),
				}),
				create("TextLabel")({
					Name = "Value",
					LayoutOrder = 2,
					Size = function()
						return UDim2.new(0, valueW(), 1, 0)
					end,
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBlack,
					Text = value,
					TextSize = valueTextSize,
					TextColor3 = Color3.fromRGB(250, 250, 245),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,

					create("UIStroke")({
						Thickness = 3,
						Color = Color3.new(0, 0, 0),
						LineJoinMode = Enum.LineJoinMode.Round,
					}),
				}),
			}),

			-- светлая линия по верху и бокам (гаснет к низу) + тёмная полоска снизу
			EdgeAccent({ Radius = radius }),
		})
	end

	-- пилюли + стрелка обжаты по содержимому; если их сумма шире Body — весь
	-- ряд ужимается через UIScale, чтобы не вылезать за границы панели
	local fit = source(1)

	local content = create("Frame")({
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,

		create("UIScale")({ Scale = fit }),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),

		pill(props.From, 1),

		-- стрелка «превращается в» (заглушка глифом; позже можно заменить на картинку)
		create("TextLabel")({
			Name = "Arrow",
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(40, pillH),
			Font = Enum.Font.GothamBlack,
			Text = "▶",
			TextSize = math.floor(pillH * 0.5),
			TextColor3 = Color3.fromRGB(150, 205, 255),

			create("UIStroke")({
				Thickness = 3,
				Color = Color3.fromRGB(28, 70, 130),
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}),

		pill(props.To, 3),
	})

	local row = create("Frame")({
		Name = "MultiplierRow",
		Size = UDim2.new(1, 0, 0, pillH),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,

		content,
	})

	-- обе пилюли одинаковой ширины: поле под число = max(TextBounds) обеих
	local valueLabels = {}
	for _, p in ipairs(content:GetChildren()) do
		if p.Name == "Pill" then
			local lbl = p:FindFirstChild("Value", true)
			if lbl then
				table.insert(valueLabels, lbl)
			end
		end
	end
	local function refitValueW()
		local w = 0
		for _, lbl in ipairs(valueLabels) do
			w = math.max(w, lbl.TextBounds.X)
		end
		if w > 0 then
			valueW(math.ceil(w) + 2)
		end
	end
	for _, lbl in ipairs(valueLabels) do
		lbl:GetPropertyChangedSignal("TextBounds"):Connect(refitValueW)
	end
	task.defer(refitValueW)

	-- AbsoluteSize не учитывает UIScale, поэтому content.AbsoluteSize.X — это
	-- «естественная» ширина ряда; делим доступную на неё
	local function refit()
		local avail = row.AbsoluteSize.X
		local natural = content.AbsoluteSize.X
		if avail > 0 and natural > 0 then
			fit(math.min(1, avail / natural))
		end
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)

	return row
end

return MultiplierRow
