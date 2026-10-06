local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local show = vide.show
local clock = rarityFx.clock

--[[
	TutorialPulse — пульсирующая рамка-подсветка поверх родителя (туториал).

	Кладётся ребёнком в элемент, который надо выделить (кнопка Base, карточка магнита/
	прокачки). Размер — вся площадь родителя, сама ничего не перехватывает (кликают
	по элементу под ней). Пока Active() == false — не создаётся вообще (нет затрат).

	  TutorialPulse({ Active = () -> boolean, Label = "NEXT UPGRADE"?, CornerRadius = UDim? })
]]

export type Props = {
	Active: () -> boolean,
	Label: string?,
	CornerRadius: UDim?,
}

local COLOR = Theme.TutorialAccent

local function wave(speed: number): number
	return math.sin(clock() * speed) * 0.5 + 0.5 -- 0..1
end

local function TutorialPulse(props: Props)
	return show(props.Active, function()
		return create("Frame")({
			Name = "TutorialPulse",
			ZIndex = 50,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create("UICorner")({ CornerRadius = props.CornerRadius or UDim.new(0, 6) }),
			create("UIStroke")({
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = COLOR,
				Thickness = function()
					return 2.5 + wave(6) * 2.5
				end,
				Transparency = function()
					return 0.45 * (1 - wave(6))
				end,
			}),

			props.Label and create("TextLabel")({
				Name = "Chip",
				ZIndex = 51,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				BackgroundColor3 = Theme.ButtonElectric,
				Font = Enum.Font.GothamBlack,
				TextSize = 13,
				TextColor3 = Color3.new(1, 1, 1),
				Text = props.Label,

				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 3),
					PaddingBottom = UDim.new(0, 3),
				}),
				create("UIStroke")({ Thickness = 2, Color = Color3.new(0, 0, 0) }),
			}) or nil,
		})
	end)
end

return TutorialPulse
