local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

--[[
	juice — общие клиентские «сочные» эффекты (только у локального игрока).

	  juice.shake(amount)              — тряска камеры; amount 0..1 («травма»),
	                                     эффекты складываются и плавно гаснут.
	  juice.fovPunch(degrees, time?)   — короткий «удар» FOV (расширить и вернуть).
	  juice.burst(position, color, count?, opts?) — разлёт искр в точке мира.
	  juice.worldText(position, text, color, opts?) — всплывающая надпись в мире (размер в studs)
	                                     (цифры урона, «+руда» и т.п.).

	Тряска применяется ПОСЛЕ стандартной камеры (RenderPriority.Camera + 1) как
	смещение поверх её CFrame — ничего не ломает в управлении камерой.
]]

local juice = {}

---- Тряска камеры (trauma-модель: сила = trauma², гаснет линейно)
local MAX_SHAKE_ANGLE = math.rad(2.2)
local MAX_SHAKE_OFFSET = 0.35
local TRAUMA_DECAY = 2.2 -- в секунду

local trauma = 0
local shakeTime = 0

RunService:BindToRenderStep("JuiceCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if trauma <= 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	shakeTime += dt
	local power = trauma * trauma
	local t = shakeTime * 28
	-- math.noise вместо random — гладкая, не дёрганая тряска
	local rx = math.noise(t, 0.1) * MAX_SHAKE_ANGLE * power
	local ry = math.noise(t, 7.3) * MAX_SHAKE_ANGLE * power
	local rz = math.noise(t, 13.7) * MAX_SHAKE_ANGLE * power
	local ox = math.noise(t, 21.1) * MAX_SHAKE_OFFSET * power
	local oy = math.noise(t, 31.9) * MAX_SHAKE_OFFSET * power

	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(rx, ry, rz)

	trauma = math.max(trauma - TRAUMA_DECAY * dt, 0)
end)

function juice.shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

---- FOV-удар
local fovOffset = Instance.new("NumberValue")
local appliedFov = 0
fovOffset.Changed:Connect(function(value)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- применяем разницу, а не абсолютное значение — не конфликтуем с другими
	-- твинами FOV (размытие за панелью в HUD тоже двигает FOV)
	camera.FieldOfView += value - appliedFov
	appliedFov = value
end)

function juice.fovPunch(degrees: number, time: number?)
	local duration = time or 0.35
	fovOffset.Value = math.max(fovOffset.Value, degrees)
	TweenService:Create(fovOffset, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Value = 0,
	}):Play()
end

---- Искры
local holder: Part? = nil
local emitter: ParticleEmitter? = nil
local holderAttachment: Attachment? = nil

local function ensureEmitter(): (Attachment, ParticleEmitter)
	if holder and holder.Parent and holderAttachment and emitter then
		return holderAttachment, emitter
	end

	local part = Instance.new("Part")
	part.Name = "JuiceFX"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(0, -500, 0)

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Enabled = false
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Lifetime = NumberRange.new(0.35, 0.7)
	pe.Speed = NumberRange.new(14, 26)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -40, 0)
	pe.Drag = 3
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-300, 300)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = attachment

	part.Parent = Workspace

	holder, holderAttachment, emitter = part, attachment, pe
	return attachment, pe
end

export type BurstOptions = { speed: number?, size: number? }

function juice.burst(position: Vector3, color: Color3, count: number?, opts: BurstOptions?)
	local attachment, pe = ensureEmitter()
	attachment.WorldPosition = position
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1):Lerp(color, 0.5))

	local speed = opts and opts.speed or 1
	pe.Speed = NumberRange.new(14 * speed, 26 * speed)
	local size = opts and opts.size or 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9 * size),
		NumberSequenceKeypoint.new(1, 0),
	})

	pe:Emit(count or 12)
end

---- Всплывающий текст в мире
export type WorldTextOptions = {
	size: number?, -- высота надписи в STUDS (как предмет в мире: дальше — мельче)
	rise: number?, -- на сколько studs всплывает
	time: number?,
	scatter: number?, -- случайный сдвиг по горизонтали, studs
}

-- Надпись не шире стольких высот (под «-1.25Qa» и т.п.)
local WORLD_TEXT_ASPECT = 4

function juice.worldText(position: Vector3, text: string, color: Color3, opts: WorldTextOptions?)
	local size = opts and opts.size or 1
	local rise = opts and opts.rise or 2
	local time = opts and opts.time or 0.8
	local scatter = opts and opts.scatter or 1.2

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
		+ Vector3.new((math.random() * 2 - 1) * scatter, 0, (math.random() * 2 - 1) * scatter)

	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	-- размер в studs (Scale), а не в пикселях: вблизи читаемо, вдали мельчает
	-- и не закрывает экран, даже если цифр много
	billboard.Size = UDim2.fromScale(size * WORLD_TEXT_ASPECT, size)
	billboard.MaxDistance = 120
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.2, 0.2)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	anchor.Parent = Workspace

	-- «поп»: выскакивает крупнее и садится в размер, потом всплывает и тает
	TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
	TweenService:Create(billboard, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, rise, 0),
	}):Play()
	local fade = TweenInfo.new(time * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, time * 0.55)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()

	Debris:AddItem(anchor, time + 0.1)
end

return juice
