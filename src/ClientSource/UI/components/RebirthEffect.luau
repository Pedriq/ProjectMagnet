local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

--[[
	RebirthEffect — короткий праздничный эффект ребёрса в стиле игрушечного LEGO-пластика.
	Всё живёт ~1.8 с и не перехватывает ввод (только Frame'ы без Active, ZIndex ниже баннеров):

	  1. мягкая вспышка цвета ребёрса (не белая — без ослепления);
	  2. два расходящихся кольца-«обода» + мягкое сияние в центре;
	  3. россыпь пластиковых кирпичиков: разлетаются вверх-в стороны, падают, крутятся, гаснут;
	  4. лёгкая цветокоррекция мира (чуть ярче и сочнее) — плавно возвращается.

	Использование:
	  local play = RebirthEffect(root)  -- root: полноэкранный Frame оверлея
	  play()
]]

local PIECE_COUNT = 30
local GRAVITY = 1100 -- px/с²
local DURATION = 1.8

local REBIRTH = Color3.fromRGB(176, 120, 255)

-- яркие чистые цвета игрушечных кирпичиков
local BRICK_COLORS = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(255, 190, 40),
	Color3.fromRGB(70, 190, 255),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(255, 255, 255),
}

local function ring(parent: Instance, delay: number, size: number, color: Color3)
	local frame = Instance.new("Frame")
	frame.Name = "RebirthRing"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.45)
	frame.Size = UDim2.fromOffset(60, 60)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 2
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 14
	stroke.Color = color
	stroke.Transparency = 0.15
	stroke.Parent = frame

	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, delay)
	TweenService:Create(frame, info, { Size = UDim2.fromOffset(size, size) }):Play()
	TweenService:Create(stroke, info, { Thickness = 2, Transparency = 1 }):Play()
	task.delay(delay + 1, function()
		frame:Destroy()
	end)
end

local function brick(parent: Instance, color: Color3)
	local piece = Instance.new("Frame")
	piece.Name = "RebirthBrick"
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Size = UDim2.fromOffset(18, 12)
	piece.BackgroundColor3 = color
	piece.BorderSizePixel = 0
	piece.ZIndex = 3
	piece.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = piece

	local edge = Instance.new("UIStroke")
	edge.Thickness = 1.5
	edge.Color = color:Lerp(Color3.new(0, 0, 0), 0.5)
	edge.Parent = piece

	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	gloss.Parent = piece

	-- шип кирпичика
	local stud = Instance.new("Frame")
	stud.AnchorPoint = Vector2.new(0.5, 1)
	stud.Position = UDim2.new(0.5, 0, 0, 2)
	stud.Size = UDim2.fromOffset(8, 4)
	stud.BackgroundColor3 = color
	stud.BorderSizePixel = 0
	stud.Parent = piece
	local studCorner = Instance.new("UICorner")
	studCorner.CornerRadius = UDim.new(0, 2)
	studCorner.Parent = stud
	local studEdge = Instance.new("UIStroke")
	studEdge.Thickness = 1.2
	studEdge.Color = edge.Color
	studEdge.Parent = stud

	return piece
end

local function RebirthEffect(root: Frame)
	local active = 0

	-- мягкая цветная вспышка по экрану
	local flash = Instance.new("Frame")
	flash.Name = "RebirthFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = REBIRTH:Lerp(Color3.new(1, 1, 1), 0.35)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = root

	-- сияние в центре
	local glow = Instance.new("Frame")
	glow.Name = "RebirthGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromOffset(120, 120)
	glow.BackgroundColor3 = REBIRTH:Lerp(Color3.new(1, 1, 1), 0.5)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 1
	glow.Parent = root
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	local function worldGrade()
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "RebirthGrade"
		cc.Parent = Lighting
		TweenService:Create(cc, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0.05,
			Saturation = 0.25,
			Contrast = 0.06,
		}):Play()
		task.delay(0.25, function()
			local out = TweenService:Create(cc, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Brightness = 0,
				Saturation = 0,
				Contrast = 0,
			})
			out.Completed:Once(function()
				cc:Destroy()
			end)
			out:Play()
		end)
	end

	return function()
		-- вспышка и сияние
		flash.BackgroundTransparency = 0.72
		TweenService:Create(flash, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()

		glow.Size = UDim2.fromOffset(120, 120)
		glow.BackgroundTransparency = 0.6
		TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(620, 620),
			BackgroundTransparency = 1,
		}):Play()

		ring(root, 0, 820, REBIRTH:Lerp(Color3.new(1, 1, 1), 0.3))
		ring(root, 0.12, 620, Color3.fromRGB(255, 200, 70))

		worldGrade()

		-- кирпичики: простая физика на Heartbeat
		local pieces = {}
		for i = 1, PIECE_COUNT do
			local angle = math.rad(-90 + (math.random() - 0.5) * 220) -- веер вверх-в стороны
			local speed = 380 + math.random() * 460
			table.insert(pieces, {
				gui = brick(root, BRICK_COLORS[(i - 1) % #BRICK_COLORS + 1]),
				x = 0,
				y = 0,
				vx = math.cos(angle) * speed,
				vy = math.sin(angle) * speed,
				spin = (math.random() - 0.5) * 720,
				rot = math.random() * 360,
				life = 1.2 + math.random() * 0.6,
			})
		end

		active += 1
		local t = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			t += dt
			local alive = false
			for _, p in ipairs(pieces) do
				if t < p.life then
					alive = true
					p.vy += GRAVITY * dt
					p.x += p.vx * dt
					p.y += p.vy * dt
					p.rot += p.spin * dt
					local gui = p.gui
					gui.Position = UDim2.new(0.5, p.x, 0.45, p.y)
					gui.Rotation = p.rot
					-- последняя треть жизни — плавное затухание
					local fade = math.clamp((t - p.life * 0.65) / (p.life * 0.35), 0, 1)
					gui.BackgroundTransparency = fade
					for _, d in ipairs(gui:GetDescendants()) do
						if d:IsA("UIStroke") then
							d.Transparency = fade
						elseif d:IsA("Frame") then
							d.BackgroundTransparency = fade
						end
					end
				elseif p.gui.Parent then
					p.gui:Destroy()
				end
			end
			if not alive or t > DURATION + 0.5 then
				conn:Disconnect()
				for _, p in ipairs(pieces) do
					p.gui:Destroy()
				end
				active -= 1
			end
		end)
	end
end

return RebirthEffect
