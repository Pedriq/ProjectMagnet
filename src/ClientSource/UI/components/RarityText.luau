local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create

local clock = rarityFx.clock
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

--[[
	RarityText — лейбл редкости меча с эффектами (для Mythic и выше).

	Effect (число, из WeaponData.effectsFor().Text):
	  0 — без эффекта: цвет редкости, слегка темнее к низу (объём), чёрная обводка
	  1 — обводка и заливка «меняются местами» по вертикали: по обводке вверх-вниз
	      ходит полоса цвета текста (обводка при этом НЕ чёрная)
	  2 — цветной градиент-блик едет по тексту слева направо
	  3 — радужный перелив едет по тексту слева направо

	Color — базовый цвет редкости (Color3). Для эффектов 2/3 сам текст белый,
	цвет даёт градиент.
]]

export type Props = {
	Text: string | () -> string,
	Color: Color3?,
	Effect: number?,

	TextSize: number?,
	Font: Enum.Font?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	TextXAlignment: Enum.TextXAlignment?,
	StrokeThickness: number?,
}

local function RarityText(props: Props)
	local effect = props.Effect or 0
	local color = props.Color or WHITE
	local strokeThickness = props.StrokeThickness or 2

	local children: { any } = {}
	local textColor: Color3 = color

	-- базовая «объёмная» заливка: тот же цвет редкости, слегка темнее к низу
	local function fillShade()
		return create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color),
				ColorSequenceKeypoint.new(1, rarityFx.darken(color, 0.32)),
			}),
		})
	end

	if effect == 1 then
		-- обводка не чёрная: её базовый цвет — затемнённая редкость, а по вертикали
		-- сквозь неё «просвечивает» цвет текста, полоса ходит вверх-вниз
		local strokeBase = rarityFx.darken(color, 0.55)
		table.insert(
			children,
			create("UIStroke")({
				Thickness = strokeThickness + 0.5,
				Color = strokeBase,
				LineJoinMode = Enum.LineJoinMode.Round,

				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, strokeBase),
						ColorSequenceKeypoint.new(0.5, color),
						ColorSequenceKeypoint.new(1, strokeBase),
					}),
					Offset = function()
						return Vector2.new(0, math.sin(clock() * 2) * 0.5)
					end,
				}),
			})
		)
		table.insert(children, fillShade())
	elseif effect == 2 then
		textColor = WHITE
		local hi = rarityFx.lighten(color, 0.75)
		table.insert(
			children,
			create("UIGradient")({
				Rotation = 0,
				Color = function()
					return rarityFx.highlightSequence(color, hi, (clock() * 0.35) % 1)
				end,
			})
		)
		table.insert(children, create("UIStroke")({
			Thickness = strokeThickness,
			Color = BLACK,
			LineJoinMode = Enum.LineJoinMode.Round,
		}))
	elseif effect == 3 then
		textColor = WHITE
		table.insert(
			children,
			create("UIGradient")({
				Rotation = 0,
				Color = function()
					return rarityFx.rainbowSequence((clock() * 0.12) % 1)
				end,
			})
		)
		table.insert(children, create("UIStroke")({
			Thickness = strokeThickness,
			Color = BLACK,
			LineJoinMode = Enum.LineJoinMode.Round,
		}))
	else
		table.insert(children, create("UIStroke")({
			Thickness = strokeThickness,
			Color = BLACK,
			LineJoinMode = Enum.LineJoinMode.Round,
		}))
		table.insert(children, fillShade())
	end

	return create("TextLabel")({
		Name = "RarityText",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 20),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Font = props.Font or Enum.Font.GothamBlack,
		TextSize = props.TextSize or 18,
		TextColor3 = textColor,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = props.Text,

		table.unpack(children),
	})
end

return RarityText
