local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local create = vide.create

--[[
	EdgeAccent — отделка кромок «сочного» элемента (кнопка, пилюля):

	  • тонкая светлая линия по контуру — верх и оба бока; на боках она гаснет
	    к низу, а у самой нижней кромки её нет;
	  • отдельный тёмный фрейм-полоска у нижней кромки — для объёма
	    (тот же приём, что Underline на полоске тайтла у Panel).

	Возвращает один Frame (во всю площадь контейнера, фон прозрачный) — просто
	добавь его последним ребёнком скруглённого элемента:

	  create("Frame")({
	      BackgroundColor3 = color,
	      create("UICorner")({ CornerRadius = radius }),
	      ...текст, иконки...
	      EdgeAccent({ Radius = radius }),
	  })
]]

export type Props = {
	ScaleLayout: boolean?,
	Radius: UDim?, -- скругление контейнера (по умолч. 8)
	ZIndex: number?, -- по умолч. без ZIndex (рисуется по порядку — добавляй последним)
	LightColor: Color3?, -- цвет контурного света (по умолч. белый)
	LightThickness: number?, -- толщина линии света (по умолч. 2.5)
	LightTransparency: number?, -- прозрачность света у верхней кромки 0..1 (по умолч. 0.42)
	Underline: boolean?, -- тёмная полоска снизу (по умолч. true)
	UnderlineColor: Color3?, -- по умолч. чёрный
	UnderlineThickness: number?, -- по умолч. 3
}

local function EdgeAccent(props: Props?)
	local p: Props = props or {}
	local radius = p.Radius or UDim.new(0, 8)
	local lightColor = p.LightColor or Color3.new(1, 1, 1)
	local lightThickness = p.LightThickness or 3.5
	local lightTop = math.clamp(p.LightTransparency or 0.35, 0, 1)
	local inset = math.max(lightThickness, 1.5)

	return create("Frame")({
		Name = "EdgeAccent",
		ZIndex = p.ZIndex,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),

		-- светлая линия по контуру: ярко сверху, к низу на боках гаснет в ноль,
		-- по нижней кромке её нет (там тёмная полоска ниже)
		create("Frame")({
			Name = "Light",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = (if p.ScaleLayout then UDim2.fromScale(0.96, 0.88) else UDim2.new(1, -inset * 2, 1, -inset * 2)),
			BackgroundTransparency = 1,

			create("UICorner")({
				CornerRadius = UDim.new(radius.Scale, math.max(radius.Offset - inset, 0)),
			}),
			create("UIStroke")({
				Thickness = lightThickness,
				Color = lightColor,
				LineJoinMode = Enum.LineJoinMode.Round,

				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, lightTop),
						NumberSequenceKeypoint.new(0.5, 0.82),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),

		-- тёмная полоска у нижней кромки — объём
		create("Frame")({
			Name = "Underline",
			Visible = p.Underline ~= false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = (if p.ScaleLayout then UDim2.fromScale(1, 0.09) else UDim2.new(1, -radius.Offset, 0, p.UnderlineThickness or 3)),
			BackgroundColor3 = p.UnderlineColor or Color3.new(0, 0, 0),
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = radius }),
			create("UIGradient")({
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.85),
					NumberSequenceKeypoint.new(1, 0.5),
				}),
			}),
		}),
	})
end

return EdgeAccent
