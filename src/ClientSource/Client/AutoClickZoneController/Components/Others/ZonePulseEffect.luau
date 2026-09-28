local TweenService = game:GetService("TweenService")

--[[
	ZonePulseEffect — лёгкая "пружинка" катушки Теслы (TeslaCoil) зоны при каждом
	автоклике: исходный размер -> плавное увеличение -> плавное возвращение к исходному.

	TeslaCoil может быть Model (тогда масштабируем через Model:ScaleTo/GetScale)
	или обычным BasePart (тогда твиним Size напрямую).

	В обоих случаях рост идёт от центра/Pivot объекта — без компенсации низ
	модели проваливался бы под пол при увеличении (Pivot большинства моделей
	стоит примерно в центре бокса, а не у земли). Поэтому при каждом изменении
	размера дополнительно подтягиваем объект по высоте так, чтобы нижняя грань
	бокса всегда совпадала с исходной — визуально объект растёт только вверх.

	Исходный размер/масштаб/нижняя точка сохраняются один раз на объект и
	переиспользуются, чтобы повторные пульсы не "уезжали" от настоящего
	исходного состояния. id-версионирование на объект защищает от гонки, если
	новый пульс прилетает раньше, чем закончился предыдущий твин (зона активна
	каждые 0.5с).
]]
local ZonePulseEffect = {}

local BOUNCE_SCALE = 1.12
local UP_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DOWN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local activeBounces = {} -- [instance] = { id, proxy?, connection?, originalScale?, originalSize? }

local function getState(instance)
	local state = activeBounces[instance]

	if not state then
		state = { id = 0 }
		activeBounces[instance] = state
	end

	return state
end

-- ScaleTo растягивает модель от её текущего Pivot — если он не у самого
-- основания (обычно это так), низ модели после увеличения провалится под пол.
-- После каждого ScaleTo сверяем фактический низ бокса с исходным и сдвигаем
-- модель по высоте на разницу, чтобы низ всегда оставался на исходном месте.
local function applyModelScale(model: Model, scaleValue: number, originalBottomY: number)
	if not model.Parent then
		return
	end

	model:ScaleTo(scaleValue)

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local currentBottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local correction = originalBottomY - currentBottomY

	if math.abs(correction) > 1e-4 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, correction, 0))
	end
end

local function bounceModel(model: Model)
	local state = getState(model)
	state.id += 1
	local myId = state.id

	if state.originalScale == nil then
		state.originalScale = model:GetScale()
	end
	local originalScale = state.originalScale

	if state.originalBottomY == nil then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		state.originalBottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	end
	local originalBottomY = state.originalBottomY

	if state.connection then
		state.connection:Disconnect()
	end
	if not state.proxy then
		state.proxy = Instance.new("NumberValue")
	end

	local proxy = state.proxy
	proxy.Value = model:GetScale()

	state.connection = proxy:GetPropertyChangedSignal("Value"):Connect(function()
		applyModelScale(model, proxy.Value, originalBottomY)
	end)

	local up = TweenService:Create(proxy, UP_INFO, { Value = originalScale * BOUNCE_SCALE })

	up.Completed:Once(function()
		if state.id ~= myId then
			return
		end

		local down = TweenService:Create(proxy, DOWN_INFO, { Value = originalScale })

		down.Completed:Once(function()
			if state.id == myId then
				applyModelScale(model, originalScale, originalBottomY)
			end
		end)

		down:Play()
	end)

	up:Play()
end

local function bouncePart(part: BasePart)
	local state = getState(part)
	state.id += 1
	local myId = state.id

	if state.originalSize == nil then
		state.originalSize = part.Size
	end
	local originalSize = state.originalSize

	if state.originalBottomY == nil then
		state.originalBottomY = part.Position.Y - originalSize.Y / 2
	end
	local originalBottomY = state.originalBottomY

	-- Size растёт от центра части — держим X/Z как есть, а Y части
	-- пересчитываем так, чтобы низ (originalBottomY) не сдвигался.
	local function positionFor(size: Vector3): Vector3
		return Vector3.new(part.Position.X, originalBottomY + size.Y / 2, part.Position.Z)
	end

	local upSize = originalSize * BOUNCE_SCALE
	local up = TweenService:Create(part, UP_INFO, { Size = upSize, Position = positionFor(upSize) })

	up.Completed:Once(function()
		if state.id ~= myId then
			return
		end

		local down =
			TweenService:Create(part, DOWN_INFO, { Size = originalSize, Position = positionFor(originalSize) })

		down.Completed:Once(function()
			if state.id == myId and part.Parent then
				part.Size = originalSize
				part.Position = positionFor(originalSize)
			end
		end)

		down:Play()
	end)

	up:Play()
end

function ZonePulseEffect:Pulse(teslaCoil: Instance)
	if not teslaCoil or not teslaCoil.Parent then
		return
	end

	if teslaCoil:IsA("Model") then
		bounceModel(teslaCoil)
	elseif teslaCoil:IsA("BasePart") then
		bouncePart(teslaCoil)
	end
end

function ZonePulseEffect.Start() end

function ZonePulseEffect.Init() end

return ZonePulseEffect
