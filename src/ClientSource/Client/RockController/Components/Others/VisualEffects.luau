local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VisualEffects = {}

local activeEffects = {}

local SHAKE_ANGLE = math.rad(6)

local SHAKE_OUT_TIME = 0.06
local SHAKE_BACK_TIME = 0.10

local FLASH_IN_TIME = 0.035
local FLASH_OUT_TIME = 0.12

local FLASH_FILL_TRANSPARENCY = 0.35

-- Страховка: если сегмент так и не долетел до игрока (персонаж пропал и т.п.) — удаляем.
local SEGMENT_LIFETIME = 3

local function getEffectData(model)
	local data = activeEffects[model]

	if not data then
		data = {
			shakeId = 0,
			flashId = 0,
			highlight = nil,
		}

		activeEffects[model] = data
	end

	return data
end

function VisualEffects:_GetHighlight(model)
	local data = getEffectData(model)

	if data.highlight and data.highlight.Parent then
		return data.highlight
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "HitHighlight"

	highlight.Adornee = model
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	highlight.Parent = model

	data.highlight = highlight

	return highlight
end

function VisualEffects:FlashRock(model)
	if not model or not model.Parent then
		return
	end

	local data = getEffectData(model)

	data.flashId += 1

	local flashId = data.flashId

	local highlight = self:_GetHighlight(model)

	-- Отменяем предыдущие tween'ы
	for _, tween in ipairs(highlight:GetChildren()) do
		if tween:IsA("Tween") then
			tween:Cancel()
		end
	end

	highlight.FillTransparency = FLASH_FILL_TRANSPARENCY

	local fadeOut =
		TweenService:Create(highlight, TweenInfo.new(FLASH_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FillTransparency = 1,
		})

	fadeOut.Completed:Once(function()
		if not model.Parent then
			return
		end

		if data.flashId ~= flashId then
			return
		end

		highlight.FillTransparency = 1
	end)

	fadeOut:Play()
end

function VisualEffects:ShakeRock(model)
	if not model or not model.Parent then
		return
	end

	local data = getEffectData(model)

	data.shakeId += 1

	local shakeId = data.shakeId

	local originalPivot = model:GetPivot()

	local direction = math.random(0, 1) == 0 and -1 or 1

	local angle = SHAKE_ANGLE * direction

	local tiltedPivot = originalPivot * CFrame.Angles(math.rad(math.random(-2, 2)), 0, angle)

	-- Сначала резко отклоняем
	local outValue = Instance.new("CFrameValue")
	outValue.Value = originalPivot

	local outConnection

	outConnection = outValue:GetPropertyChangedSignal("Value"):Connect(function()
		if not model.Parent then
			outConnection:Disconnect()
			outValue:Destroy()
			return
		end

		model:PivotTo(outValue.Value)
	end)

	local outTween =
		TweenService:Create(outValue, TweenInfo.new(SHAKE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = tiltedPivot,
		})

	outTween.Completed:Once(function()
		outConnection:Disconnect()
		outValue:Destroy()

		if not model.Parent then
			return
		end

		if data.shakeId ~= shakeId then
			return
		end

		-- Возвращаем плавно
		local backValue = Instance.new("CFrameValue")
		backValue.Value = model:GetPivot()

		local backConnection

		backConnection = backValue:GetPropertyChangedSignal("Value"):Connect(function()
			if not model.Parent then
				backConnection:Disconnect()
				backValue:Destroy()
				return
			end

			model:PivotTo(backValue.Value)
		end)

		local backTween = TweenService:Create(
			backValue,
			TweenInfo.new(SHAKE_BACK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Value = originalPivot,
			}
		)

		backTween.Completed:Once(function()
			backConnection:Disconnect()
			backValue:Destroy()

			if model.Parent and data.shakeId == shakeId then
				model:PivotTo(originalPivot)
			end
		end)

		backTween:Play()
	end)

	outTween:Play()
end

function VisualEffects:HitRock(model)
	if not model or not model.Parent then
		return
	end

	self:ShakeRock(model)
	self:FlashRock(model)
end

--[[
	«Магнит»: отколотый сегмент сначала коротко отскакивает от камня (POP),
	потом с разгоном летит в HumanoidRootPart игрока, уменьшается на подлёте
	и исчезает. Двигаем вручную (Anchored + CFrame) одним общим Heartbeat —
	без физики полёт предсказуемый и догоняет бегущего игрока.
]]
local POP_TIME = 0.25 -- сколько длится отскок от камня
local POP_GRAVITY = 60
local HOME_START_SPEED = 20
local HOME_ACCEL = 140
local HOME_MAX_SPEED = 120
local HOME_TURN_RATE = 10 -- насколько резко доворачивает на игрока
local SHRINK_DISTANCE = 6 -- с какой дистанции начинает уменьшаться
local COLLECT_DISTANCE = 1.5 -- «долетел» — исчезает

local flyingSegments = {}
local flyConnection: RBXScriptConnection? = nil

local function getTargetPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function stepFlyingSegments(dt: number)
	local target = getTargetPosition()

	for i = #flyingSegments, 1, -1 do
		local s = flyingSegments[i]
		local part = s.part
		s.age += dt

		local done = not part.Parent or not target or s.age > SEGMENT_LIFETIME

		if not done then
			if s.age < POP_TIME then
				s.velocity += Vector3.new(0, -POP_GRAVITY * dt, 0)
			else
				local toTarget = target - s.position
				local speed = math.min(HOME_START_SPEED + HOME_ACCEL * (s.age - POP_TIME), HOME_MAX_SPEED)
				if toTarget.Magnitude > 1e-3 then
					s.velocity = s.velocity:Lerp(toTarget.Unit * speed, math.min(1, HOME_TURN_RATE * dt))
				end
			end

			s.position += s.velocity * dt
			s.rotation *= CFrame.Angles(s.spin.X * dt, s.spin.Y * dt, s.spin.Z * dt)
			part.CFrame = CFrame.new(s.position) * s.rotation

			local distance = (target - s.position).Magnitude
			if s.age >= POP_TIME and distance < SHRINK_DISTANCE then
				part.Size = s.size * math.max(distance / SHRINK_DISTANCE, 0.15)
			end

			done = s.age >= POP_TIME and distance <= COLLECT_DISTANCE
		end

		if done then
			part:Destroy()
			table.remove(flyingSegments, i)
		end
	end

	if #flyingSegments == 0 and flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end

function VisualEffects:BreakSegment(segment)
	if not segment or not segment:IsA("BasePart") then
		return
	end

	if segment:GetAttribute("Broken") then
		return
	end

	segment:SetAttribute("Broken", true)

	local weld = segment:FindFirstChildOfClass("WeldConstraint")

	if weld then
		weld:Destroy()
	end

	segment.Parent = workspace
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanTouch = false
	segment.CanQuery = false

	local cf = segment.CFrame
	table.insert(flyingSegments, {
		part = segment,
		age = 0,
		position = cf.Position,
		rotation = cf - cf.Position,
		size = segment.Size,
		velocity = Vector3.new(math.random(-10, 10), math.random(15, 25), math.random(-10, 10)),
		spin = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10)),
	})

	if not flyConnection then
		flyConnection = RunService.Heartbeat:Connect(stepFlyingSegments)
	end
end

-- Сколько живёт «скорлупа» модели после того, как все сегменты разлетелись.
-- Сегменты уже отвязаны в workspace со своим Debris (SEGMENT_LIFETIME) — держим
-- модель ровно на время финальной вспышки.
local SHATTER_MODEL_CLEANUP = 0.3

--[[
	Финальный развал камня по смертельному удару. Отвязан от лайфтайма модели:
	раньше DeleteRockVisual делал visualData.Model:Destroy() сразу, и при ваншоте
	импакт (flash + разлёт сегментов) не успевал проиграться — модель исчезала
	в тот же кадр, а то и раньше remote-хендлера HitRock. Здесь бьём все
	оставшиеся сегменты физикой, даём вспышку и чистим «скорлупу» отложенно.
]]
function VisualEffects:ShatterRock(model)
	if not model or model:GetAttribute("Shattered") then
		return
	end
	model:SetAttribute("Shattered", true)

	if model.Parent then
		self:FlashRock(model)

		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and tonumber(child.Name) then
				self:BreakSegment(child)
			end
		end
	end

	local data = activeEffects[model]
	if data then
		-- гасим возможные висящие shake/flash-твины по старому id
		data.shakeId += 1
	end

	Debris:AddItem(model, SHATTER_MODEL_CLEANUP)
	task.delay(SHATTER_MODEL_CLEANUP, function()
		activeEffects[model] = nil
	end)
end

function VisualEffects:DestroyRockEffects(model)
	local data = activeEffects[model]

	if not data then
		return
	end

	data.shakeId += 1
	data.flashId += 1

	if data.highlight then
		data.highlight:Destroy()
	end

	activeEffects[model] = nil
end

function VisualEffects.Start() end

function VisualEffects.Init() end

return VisualEffects
