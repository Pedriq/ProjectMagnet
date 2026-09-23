local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local Surface = require(ReplicatedStorage.ClientSource.UI.components.Surface)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)

local create = vide.create
local asset = Format.asset

--[[
	BuffChip — один активный временный бафф в ActiveBuffsBar (правый нижний угол):

	  ┌──────┐╮ x2
	  │ icon │
	  └──────┘
	  [ 9:59 ]  <- таймер

	Иконка — цветная плитка (цвет = тип баффа: оранжевый Strength, зелёный Money,
	см. ActiveBuffsBar), "x2" — бейдж в правом верхнем углу плитки, таймер —
	отдельная пилюля под иконкой.
]]

export type Props = {
	Icon: string,
	Color: Color3,
	Multiplier: string | () -> string, -- напр. "x2"
	TimeLeft: string | () -> string, -- напр. "9:59"
	LayoutOrder: number?,
}

local ICON_SIZE = 60
local RADIUS = UDim.new(0, 10)

local function BuffChip(props: Props)
	return create("Frame")({
		Name = "BuffChip",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE + 26),
		BackgroundTransparency = 1,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),

		--== плитка-иконка ==
		create("Frame")({
			Name = "IconTile",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundColor3 = props.Color,
			BackgroundTransparency = 0.12,
			ClipsDescendants = false,

			create("UICorner")({ CornerRadius = RADIUS }),
			create("UIStroke")({ Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.15 }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.55, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.new(0.78, 0.78, 0.78)),
				}),
			}),

			create("ImageLabel")({
				Name = "Icon",
				ZIndex = 2,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.62, 0.62),
				ScaleType = Enum.ScaleType.Fit,
				Image = asset(props.Icon),
			}),

			create("TextLabel")({
				Name = "Multiplier",
				ZIndex = 3,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 6, 0, -8),
				Size = UDim2.fromOffset(30, 22),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				Text = props.Multiplier,
				TextColor3 = Color3.new(1, 1, 1),

				create("UIStroke")({
					Thickness = 2,
					Color = Color3.new(0, 0, 0),
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			}),

			table.unpack(Surface({
				Radius = RADIUS,
				TileSize = UDim2.fromOffset(20, 20),
				TextureTransparency = 0.86,
				Highlight = 0.4,
				Shadow = 0.3,
			})),
			EdgeAccent({ Radius = RADIUS }),
		}),

		--== таймер под иконкой ==
		create("Frame")({
			Name = "Timer",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(ICON_SIZE, 22),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,

			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),

			create("TextLabel")({
				Name = "Value",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				Text = props.TimeLeft,

				create("UITextSizeConstraint")({ MaxTextSize = 16 }),
				create("UIStroke")({ Thickness = 1.5, Color = Color3.new(0, 0, 0) }),
			}),
		}),
	})
end

return BuffChip
