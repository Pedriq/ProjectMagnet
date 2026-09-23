local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local create = vide.create

export type Props = {
	Icon: string,
	Text: string | () -> string,
	Large: boolean?,
	FadeStart: number?,
	FadePower: number?,
	LayoutOrder: number?,
	TextColor: Color3?,
}

-- ease-in кривая затухания: NumberSequence линеен между точками, поэтому
-- набиваем несколько точек по a^power — чем больше power, тем сильнее «прибивает»
-- к правому краю.
local function fadeCurve(fadeStart: number, power: number): NumberSequence
	local kp = { NumberSequenceKeypoint.new(0, 0) }
	if fadeStart > 0 then
		table.insert(kp, NumberSequenceKeypoint.new(fadeStart, 0))
	end
	local steps = 6
	for i = 1, steps - 1 do
		local a = i / steps
		table.insert(kp, NumberSequenceKeypoint.new(fadeStart + a * (1 - fadeStart), a ^ power))
	end
	table.insert(kp, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(kp)
end

local function StatRow(props: Props)
	local height = props.Large and 44 or 32
	local iconSize = props.Large and 34 or 24
	local textSize = props.Large and 30 or 23
	local textColor = props.TextColor or Color3.fromRGB(230, 233, 230)
	local fadeStart = math.clamp(props.FadeStart or 0.3, 0, 0.95)
	local fadePower = math.max(props.FadePower or 1, 1)

	local fade = fadeCurve(fadeStart, fadePower)

	-- Обычный Frame (не CanvasGroup): UIGradient действует только на сам Frame и
	-- НЕ распространяется на детей. Поэтому фон + обводка гаснут к правому краю,
	-- а иконка и текст остаются нетронутыми.
	return create("Frame")({
		Name = "StatRow",
		Size = UDim2.new(0.5, 0, 0, height),
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = Color3.fromRGB(35, 25, 45),
		BackgroundTransparency = 0.7,

		create("UIGradient")({ Transparency = fade }), -- гасит фон

		create("UICorner")({ CornerRadius = UDim.new(0, 1) }),
		create("UIStroke")({
			Thickness = 1.5,
			Color = Color3.fromRGB(0, 0, 0),
			Transparency = 0,

			create("UIGradient")({ Transparency = fade }),
		}),

		create("ImageLabel")({
			Name = "Icon",
			Image = Format.asset(props.Icon),
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize),
		}),

		create("TextLabel")({
			Name = "Value",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8 + iconSize + 8, 0.5, 0),
			Size = UDim2.new(1, -(8 + iconSize + 16), 1, 0),
			Font = Enum.Font.GothamBlack,
			TextSize = textSize,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = textColor,
			Text = props.Text,

			create("UIStroke")({
				Thickness = 1.5,
				Color = Color3.new(0, 0, 0),
			}),
		}),
	})
end

return StatRow
