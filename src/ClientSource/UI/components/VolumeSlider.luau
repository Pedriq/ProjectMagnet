local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local create = vide.create
local source = vide.source
local spring = vide.spring
local cleanup = vide.cleanup

local asset = Format.asset

--[[
	VolumeSlider — строка-карточка с ползунком громкости (окно Settings).

	  ┌───────────────────────────────────────┐
	  │ Music                             70% │
	  │ ████████████████●─────────────────────│
	  └───────────────────────────────────────┘

	Тянется мышью и пальцем: нажатие на дорожку ставит значение сразу, дальше ведёт
	за курсором, пока кнопка зажата (даже за пределами дорожки). Звук-подтверждение —
	при отпускании.
]]

export type Props = {
	Label: string,
	Value: () -> number, -- 0..1
	OnChanged: (value: number) -> (),
	OnCommitted: ((value: number) -> ())?, -- значение зафиксировано (отпустили ползунок / закрыли окно во время drag): сохранить
	Color: Color3?, -- цвет заполнения (по умолч. Theme.ButtonElectric)
	LayoutOrder: number?,
}

local KNOB = 26
local TEXTURE = "119993804734501"

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function VolumeSlider(props: Props)
	local color = props.Color or Theme.ButtonElectric
	local dragging = source(false)
	local hovered = source(false)

	local knobScale = spring(function()
		if dragging() then
			return 1.18
		end
		return hovered() and 1.1 or 1
	end, 0.16)

	local track: Frame? = nil

	local function setFromX(x: number)
		if not track then
			return
		end
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		props.OnChanged(math.clamp((x - track.AbsolutePosition.X) / width, 0, 1))
	end

	local moveConn = UserInputService.InputChanged:Connect(function(input)
		if dragging() and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	local endConn = UserInputService.InputEnded:Connect(function(input)
		if dragging() and isPress(input) then
			dragging(false)
			sfx.play("ClickUI", { pitch = 0.8 + props.Value() * 0.6 })
			if props.OnCommitted then
				props.OnCommitted(props.Value())
			end
		end
	end)
	cleanup(function()
		moveConn:Disconnect()
		endConn:Disconnect()
		-- окно закрыли посреди drag: InputEnded уже не придёт — сохраняем то, что выставлено
		if dragging() and props.OnCommitted then
			props.OnCommitted(props.Value())
		end
	end)

	local function percent(): string
		return `{math.floor(props.Value() * 100 + 0.5)}%`
	end

	local function stroke(thickness: number)
		return create("UIStroke")({ Thickness = thickness, Color = Color3.new(0, 0, 0), Transparency = 0.1 })
	end

	local function textStroke()
		return create("UIStroke")({ Thickness = 2, Color = Color3.new(0, 0, 0), LineJoinMode = Enum.LineJoinMode.Round })
	end

	track = create("Frame")({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -14),
		Size = UDim2.new(1, -32, 0, 18),
		BackgroundColor3 = Theme.Steel900,

		create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		stroke(3),

		-- заполнение: градиент цвета (верх светлее) + общая тайловая текстура
		create("Frame")({
			Name = "Fill",
			Size = function()
				return UDim2.fromScale(props.Value(), 1)
			end,
			BackgroundColor3 = color,
			ClipsDescendants = true,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.72, 0.72, 0.72)),
			}),
			create("ImageLabel")({
				Name = "Texture",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = asset(TEXTURE),
				ImageTransparency = 0.7,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(18, 18),
			}),
		}),

		-- ручка
		create("Frame")({
			Name = "Knob",
			ZIndex = 2,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.fromScale(props.Value(), 0.5)
			end,
			Size = function()
				local s = KNOB * knobScale()
				return UDim2.fromOffset(s, s)
			end,
			BackgroundColor3 = Theme.Text,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			stroke(2.5),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(184, 192, 204)),
			}),
		}),
	}) :: Frame

	return create("Frame")({
		Name = "VolumeSlider_" .. props.Label,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = Theme.Steel700,
		BackgroundTransparency = 0.1,

		create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
		stroke(2),

		create("TextLabel")({
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(0.6, 0, 0, 30),
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = props.Label,

			textStroke(),
		}),
		create("TextLabel")({
			Name = "Percent",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 10),
			Size = UDim2.new(0.3, 0, 0, 30),
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45),
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = percent,

			textStroke(),
		}),

		track,

		-- зона нажатия выше дорожки: по высоте с запасом под палец
		create("TextButton")({
			Name = "Hit",
			ZIndex = 3,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 8, 1, -4),
			Size = UDim2.new(1, -16, 0, 42),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			MouseEnter = function()
				hovered(true)
			end,
			MouseLeave = function()
				hovered(false)
			end,
			InputBegan = function(input: InputObject)
				if isPress(input) then
					dragging(true)
					setFromX(input.Position.X)
				end
			end,
		}),
	})
end

return VolumeSlider
