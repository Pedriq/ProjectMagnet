local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local perf = require(ReplicatedStorage.ClientSource.perf)

local VisualEffects = {}

local activeEffects = {}

local SHAKE_ANGLE = math.rad(6)

local SHAKE_OUT_TIME = 0.06
local SHAKE_BACK_TIME = 0.10

local FLASH_IN_TIME = 0.035
local FLASH_OUT_TIME = 0.12

local FLASH_FILL_TRANSPARENCY = 0.35

-- «Магнит»: отколотый сегмент сначала чуть выскакивает из камня вверх/вбок,
-- затем по дуге с ускорением летит в игрока, уменьшается и исчезает.
local MAGNET_POP_HEIGHT = 1 -- лёгкий изгиб траектории вверх (0 = строго по прямой)
local MAGNET_POP_SPREAD = 1 -- случайный разброс изгиба по горизонтали
local MAGNET_TIME_MIN = 0.45 -- длительность полёта, сек (случайно в диапазоне)
local MAGNET_TIME_MAX = 0.65
local MAGNET_SHRINK_FROM = 0.55 -- с какой доли пути сегмент начинает уменьшаться
local MAGNET_END_SCALE = 0.1 -- размер в момент «присасывания» (доля исходного)
local MAGNET_SPIN_MAX = 12 -- рад/сек, вращение в полёте
local MAGNET_TARGET_OFFSET = Vector3.new(0, 0.5, 0) -- точка на игроке (от HumanoidRootPart)

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
	-- Highlight на мобильных дорогой (и есть лимит одновременных Highlight в движке) — там вспышки нет
	if perf.isMobile or not model or not model.Parent then
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

	-- От покойного положения (RockVisualizer), а не от текущего: камень может быть
	-- наклонён магнитным дрожанием (MagnetWobble) — иначе вернулся бы в наклон.
	local originalPivot = model:GetAttribute("BasePivot") or model:GetPivot()

	-- пока идёт тряска удара, MagnetWobble не трогает камень (IsHitShaking)
	data.hitShakeUntil = os.clock() + SHAKE_OUT_TIME + SHAKE_BACK_TIME

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

-- Сегменты, летящие в игрока. Двигаются одним общим Heartbeat-циклом, который
-- подключён только пока в полёте есть хоть один сегмент.
-- Сегмент может быть как одиночным BasePart (кубик), так и Model (сборка из
-- нескольких частей на один осколок) — обе ветки двигаются одинаково через
-- PivotTo/GetPivot, единственная разница в способе "сжатия" при засасывании.
local flying = {}
local flyConnection: RBXScriptConnection? = nil

local function isSegmentInstance(inst): boolean
	return inst ~= nil and (inst:IsA("BasePart") or inst:IsA("Model"))
end

local function segmentPivot(segment): CFrame
	if segment:IsA("Model") then
		return segment:GetPivot()
	end
	return segment.CFrame
end

local function setSegmentPivot(segment, cframe: CFrame)
	if segment:IsA("Model") then
		segment:PivotTo(cframe)
	else
		segment.CFrame = cframe
	end
end

-- factor — доля от исходного размера (1 = как было, MAGNET_END_SCALE = в момент засасывания).
local function setSegmentScale(segment, factor: number, baseSize: Vector3?)
	if segment:IsA("Model") then
		-- ScaleTo у Model — самая дорогая операция полёта; на мобильных не чаще, чем
		-- при заметном (>6%) изменении масштаба
		local last = segment:GetAttribute("LastScale")
		if perf.isMobile and last and math.abs(last - factor) < 0.06 and factor > MAGNET_END_SCALE then
			return
		end
		segment:SetAttribute("LastScale", factor)
		segment:ScaleTo(factor)
	else
		segment.Size = (baseSize :: Vector3) * factor
	end
end

local function magnetTarget(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position + MAGNET_TARGET_OFFSET
end

-- Кусочек долетел до игрока: «чпок» с растущим тоном — цепочка подряд
-- прилетевших кусочков звучит как восходящая гамма (классический «collect»-фидбек).
-- Пауза дольше ORE_CHAIN_RESET — цепочка начинается заново с низкого тона.
local ORE_CHAIN_RESET = 0.45
local ORE_CHAIN_MAX = 16
local oreChain = 0
local lastAbsorb = 0

local function onPieceAbsorbed()
	local now = os.clock()
	if now - lastAbsorb > ORE_CHAIN_RESET then
		oreChain = 0
	end
	lastAbsorb = now
	oreChain = math.min(oreChain + 1, ORE_CHAIN_MAX)
	sfx.play("OrePop", { pitch = 0.9 + oreChain * 0.05, volume = 0.8 })
end

local function stepFlying()
	local now = os.clock()
	-- Цель берётся каждый кадр — сегмент догоняет игрока, даже если тот бежит.
	local target = magnetTarget()

	for i = #flying, 1, -1 do
		local f = flying[i]
		local part = f.part

		if not part.Parent then
			table.remove(flying, i)
			continue
		end

		local elapsed = now - f.startTime
		if elapsed < 0 then
			continue -- ещё ждёт своей очереди (стаггер при полном разрушении)
		end

		if target then
			f.goal = target
		end

		local t = math.clamp(elapsed / f.duration, 0, 1)
		-- Сразу летит к игроку (стартовая скорость не нулевая, в отличие от t*t,
		-- где кусок первые кадры почти стоял на месте) и ускоряется к концу —
		-- «засасывание» магнитом.
		local e = t * (1 + t) / 2

		-- Квадратичная кривая Безье: старт -> точка дуги над камнем -> игрок.
		local position = f.startPos:Lerp(f.control, e):Lerp(f.control:Lerp(f.goal, e), e)
		setSegmentPivot(
			part,
			CFrame.new(position) * f.startRotation * CFrame.fromAxisAngle(f.spinAxis, f.spinSpeed * elapsed)
		)

		if t > MAGNET_SHRINK_FROM then
			local k = (t - MAGNET_SHRINK_FROM) / (1 - MAGNET_SHRINK_FROM)
			setSegmentScale(part, 1 - (1 - MAGNET_END_SCALE) * k, f.baseSize)
		end

		if t >= 1 then
			part:Destroy()
			table.remove(flying, i)
			onPieceAbsorbed()
		end
	end

	if #flying == 0 and flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end

-- delay — задержка старта полёта (для «ручейка» сегментов при полном разрушении).
function VisualEffects:BreakSegment(segment, delay: number?)
	if not isSegmentInstance(segment) then
		return
	end

	if segment:GetAttribute("Broken") then
		return
	end

	segment:SetAttribute("Broken", true)

	-- Массовое разрушение (бег по полю на мобильном): лишние кусочки не летят, а просто
	-- исчезают — руда начисляется сервером независимо от визуала.
	if #flying >= perf.maxFlying then
		segment:Destroy()
		return
	end

	-- Внутри Model осколка части держатся на весу через WeldConstraint к
	-- остальной части камня (как и одиночный кубик) — рвём все такие связи
	-- и жёстко анкорим всё, что внутри, иначе куски разлетятся сами по себе
	-- под гравитацией ещё до начала полёта к игроку.
	local isModel = segment:IsA("Model")
	-- один проход по осколку (раньше GetDescendants вызывался дважды): рвём сварки и анкорим части
	for _, inst in ipairs(segment:GetDescendants()) do
		if inst:IsA("WeldConstraint") then
			inst:Destroy()
		elseif isModel and inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanTouch = false
			inst.CanQuery = false
		end
	end

	local startCFrame = segmentPivot(segment)

	if isModel then
		-- части уже заанкорены выше
	else
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanTouch = false
		segment.CanQuery = false
	end

	segment.Parent = workspace

	local goal = magnetTarget()
	if not goal then
		-- Персонажа нет (респавн) — лететь некуда, просто убираем кусок.
		segment:Destroy()
		return
	end

	local startPos = startCFrame.Position
	local duration = MAGNET_TIME_MIN + math.random() * (MAGNET_TIME_MAX - MAGNET_TIME_MIN)
	local startDelay = delay or 0

	table.insert(flying, {
		part = segment,
		startPos = startPos,
		control = startPos
			+ Vector3.new(
				(math.random() * 2 - 1) * MAGNET_POP_SPREAD,
				MAGNET_POP_HEIGHT,
				(math.random() * 2 - 1) * MAGNET_POP_SPREAD
			),
		goal = goal,
		startTime = os.clock() + startDelay,
		duration = duration,
		baseSize = if segment:IsA("BasePart") then segment.Size else nil,
		startRotation = startCFrame.Rotation,
		spinAxis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
		spinSpeed = (math.random() * 2 - 1) * MAGNET_SPIN_MAX,
	})

	-- Страховка: если цикл по какой-то причине не доведёт кусок до конца.
	Debris:AddItem(segment, startDelay + duration + 1)

	if not flyConnection then
		flyConnection = RunService.Heartbeat:Connect(stepFlying)
	end
end

-- Сколько живёт «скорлупа» модели после того, как все сегменты разлетелись.
-- Сегменты уже отвязаны в workspace и летят в игрока сами — держим модель
-- ровно на время финальной вспышки.
local SHATTER_MODEL_CLEANUP = 0.3

--[[
	Финальный развал камня по смертельному удару. Отвязан от лайфтайма модели:
	раньше DeleteRockVisual делал visualData.Model:Destroy() сразу, и при ваншоте
	импакт (flash + разлёт сегментов) не успевал проиграться — модель исчезала
	в тот же кадр, а то и раньше remote-хендлера HitRock. Здесь все оставшиеся
	сегменты сразу летят в игрока, даём вспышку и чистим «скорлупу» отложенно.
]]
function VisualEffects:ShatterRock(model)
	if not model or model:GetAttribute("Shattered") then
		return
	end
	model:SetAttribute("Shattered", true)

	if model.Parent then
		self:FlashRock(model)

		for _, child in ipairs(model:GetChildren()) do
			if isSegmentInstance(child) and tonumber(child.Name) then
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

-- Идёт ли сейчас тряска от удара (ShakeRock) — MagnetWobble в это время молчит,
-- чтобы две анимации не дёргали pivot одновременно.
function VisualEffects:IsHitShaking(model): boolean
	local data = activeEffects[model]
	return data ~= nil and (data.hitShakeUntil or 0) > os.clock()
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
