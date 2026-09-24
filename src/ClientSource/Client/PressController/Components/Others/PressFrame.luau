local RunService = game:GetService("RunService")

--[[
	PressFrame — ЛОКАЛЬНАЯ анимация рамы пресса Workspace.HydraulicPress.Press:
	  Left / Right — ножки (растягиваются вверх, низ остаётся на месте);
	  Middle       — балка сверху (едет вверх/вниз);
	  Press        — головка под центром Middle, над PressInventory (едет вместе с Middle).
	Допускаются опечатки в именах: Rigth, Moddle.

	  * Рама держит головку над кучкой руды: SetPileTop(y) — ножки вытягиваются,
	    Middle + Press поднимаются так, чтобы низ головки был на CLEARANCE выше кучки;
	  * SlamAsync(y) — Middle + Press опускаются до y (удар), yield до момента удара,
	    дальше поднимаются обратно уже без yield.

	Меняем свойства серверных деталей на клиенте — это не реплицируется, другие
	игроки видят свою (или исходную) раму.
]]
local PressFrame = {}

---- Datas
local NAMES = {
	Left = { "Left" },
	Right = { "Right", "Rigth" },
	Middle = { "Middle", "Moddle" },
	Head = { "Press" },
}

local CLEARANCE = 1.5 -- зазор между низом головки и верхом кучки, studs
local LIFT_SPEED = 6 -- скорость подстройки высоты рамы (чем больше — тем резче)
local SLAM_IMPACT_OFFSET = 0.1 -- головка останавливается чуть выше кучки
local SLAM_RISE_TIME = 0.35

---- State
type PartState = { Part: BasePart, CFrame: CFrame, Size: Vector3, Axis: Vector3? }

local legs: { PartState } = {}
local movers: { PartState } = {} -- Middle + Press
local headBottom0 = 0 -- низ головки в исходном положении (мировой Y)
local targetLift = 0
local currentLift = 0
local slamOffset = 0
local slamToken = 0
local ready = false

-- Полувысота детали по мировой Y (с учётом поворота).
local function worldHalfHeight(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
		/ 2
end

-- Локальная ось детали, которая смотрит вверх (по ней ножка растягивается).
local function verticalSizeAxis(part: BasePart): Vector3
	local cf = part.CFrame
	local x, y, z = math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y)
	if y >= x and y >= z then
		return Vector3.yAxis
	elseif x >= z then
		return Vector3.xAxis
	end
	return Vector3.zAxis
end

local function findIn(model: Instance, names: { string }): BasePart?
	for _, name in ipairs(names) do
		local found = model:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

local function capture(part: BasePart, withAxis: boolean): PartState
	return {
		Part = part,
		CFrame = part.CFrame,
		Size = part.Size,
		Axis = if withAxis then verticalSizeAxis(part) else nil,
	}
end

local function apply()
	for _, state in ipairs(legs) do
		state.Part.Size = state.Size + (state.Axis :: Vector3) * currentLift
		state.Part.CFrame = state.CFrame + Vector3.yAxis * (currentLift / 2)
	end
	local offset = Vector3.yAxis * (currentLift - slamOffset)
	for _, state in ipairs(movers) do
		state.Part.CFrame = state.CFrame + offset
	end
end

-- Текущий низ головки (мировой Y).
function PressFrame:GetHeadBottom(): number
	return headBottom0 + currentLift - slamOffset
end

-- Кучка руды: baseY — дно (пустая кучка), pileTopY — текущий верх (мировой Y).
-- Рама поднимается ровно на высоту кучки (головка сохраняет свой исходный зазор),
-- и не меньше, чем нужно, чтобы головка была на CLEARANCE выше руды.
function PressFrame:SetPile(baseY: number, pileTopY: number)
	if not ready then
		return
	end
	targetLift = math.max(0, pileTopY - baseY, pileTopY + CLEARANCE - headBottom0)
end

-- Удар: Middle + Press опускаются до targetY. Yield до удара (PressConfig.SLAM_TIME),
-- подъём обратно — уже в фоне.
function PressFrame:SlamAsync(targetY: number, duration: number)
	if not ready then
		task.wait(duration)
		return
	end

	slamToken += 1
	local token = slamToken
	local startOffset = slamOffset
	local distance = math.max(0, (headBottom0 + currentLift) - (targetY + SLAM_IMPACT_OFFSET))

	local t = 0
	while t < duration and token == slamToken do
		t += RunService.Heartbeat:Wait()
		local alpha = math.min(t / duration, 1)
		slamOffset = startOffset + (distance - startOffset) * alpha * alpha -- с ускорением
	end
	if token ~= slamToken then
		return
	end
	slamOffset = distance

	task.spawn(function()
		local from = slamOffset
		local rt = 0
		while rt < SLAM_RISE_TIME and token == slamToken do
			rt += RunService.Heartbeat:Wait()
			local alpha = math.min(rt / SLAM_RISE_TIME, 1)
			slamOffset = from * (1 - alpha) ^ 2
		end
		if token == slamToken then
			slamOffset = 0
		end
	end)
end

function PressFrame:IsReady(): boolean
	return ready
end

-- Найти детали рамы и запустить анимацию. Возвращает false, если деталей пока нет
-- (StreamingEnabled: у клиента они появляются, только когда игрок рядом) —
-- тогда PressVisualizer позовёт Setup ещё раз позже.
function PressFrame:Setup(frame: Instance?): boolean
	if ready or not frame then
		return ready
	end

	local left = findIn(frame, NAMES.Left)
	local right = findIn(frame, NAMES.Right)
	local middle = findIn(frame, NAMES.Middle)
	local head = findIn(frame, NAMES.Head)
	if not (left and right and middle and head) then
		return false
	end

	-- Локально: всё заякорено, сварки внутри рамы выключены — иначе сдвиг одной
	-- детали через CFrame потащил бы за собой приваренные.
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d.Enabled = false
		end
	end

	legs = { capture(left, true), capture(right, true) }
	movers = { capture(middle, false), capture(head, false) }
	headBottom0 = head.Position.Y - worldHalfHeight(head)
	currentLift, slamOffset = 0, 0
	ready = true
	print(
		string.format(
			"[Press] рама найдена: %s, %s, %s, %s; низ головки Y=%.2f",
			left.Name,
			right.Name,
			middle.Name,
			head.Name,
			headBottom0
		)
	)

	local appliedLift, appliedSlam = 0, 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		-- рама выгрузилась стримингом — ждём, пока появится снова, и настраиваемся заново
		for _, state in ipairs(legs) do
			if not state.Part.Parent then
				ready = false
			end
		end
		for _, state in ipairs(movers) do
			if not state.Part.Parent then
				ready = false
			end
		end
		if not ready then
			connection:Disconnect()
			return
		end

		currentLift += (targetLift - currentLift) * math.min(1, dt * LIFT_SPEED)
		if math.abs(targetLift - currentLift) < 0.005 then
			currentLift = targetLift
		end
		if currentLift ~= appliedLift or slamOffset ~= appliedSlam then
			appliedLift, appliedSlam = currentLift, slamOffset
			apply()
		end
	end)
	return true
end

function PressFrame.Start() end

function PressFrame.Init() end

return PressFrame
