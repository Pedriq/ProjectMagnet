local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[
	Разгрузка руды на прессе: на каждый снятый сервером кусочек (сигнал
	PlayerManagerService.UnloadOrePiece) из игрока вылетает случайный кусочек
	этой руды (ReplicatedStorage.Assets.Ores.<oreName>) и по дуге летит в
	Workspace.HydraulicPress.PressInventory, где исчезает. Чисто визуал —
	инвентарь уже изменён на сервере.
]]
local OreUnloadEffects = {}

local FLIGHT_TIME = 0.45
local ARC_HEIGHT = 8
-- Разброс точки вылета и приземления, чтобы поток кусочков не шёл одной линией.
local SPAWN_SPREAD = 1.5
local TARGET_SPREAD = 1

local oreAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Ores")

local pressInventory: BasePart? = nil
local flying = {}
local flyConnection: RBXScriptConnection? = nil

local function getPressInventory(): BasePart?
	if pressInventory and pressInventory.Parent then
		return pressInventory
	end
	local press = workspace:FindFirstChild("HydraulicPress")
	pressInventory = press and press:FindFirstChild("PressInventory")
	return pressInventory
end

local function randomOffset(spread: number): Vector3
	return Vector3.new((math.random() * 2 - 1) * spread, 0, (math.random() * 2 - 1) * spread)
end

-- Кусочек может быть как Part, так и Model — делаем его «призраком» без физики.
local function prepareVisual(visual: Instance)
	local parts = if visual:IsA("BasePart") then { visual } else {}
	for _, d in ipairs(visual:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for _, p in ipairs(parts) do
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
end

local function step(dt: number)
	for i = #flying, 1, -1 do
		local f = flying[i]
		f.t += dt / FLIGHT_TIME

		if f.t >= 1 or not f.visual.Parent then
			f.visual:Destroy()
			table.remove(flying, i)
			continue
		end

		-- Квадратичная кривая Безье: старт → верх дуги → пресс.
		local t = f.t
		local pos = (1 - t) ^ 2 * f.from + 2 * (1 - t) * t * f.control + t ^ 2 * f.to
		f.rotation *= CFrame.Angles(f.spin.X * dt, f.spin.Y * dt, f.spin.Z * dt)
		f.visual:PivotTo(CFrame.new(pos) * f.rotation)
	end

	if #flying == 0 and flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
end

function OreUnloadEffects:PlayUnload(player: Player, oreName: string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = getPressInventory()
	if not root or not target then
		return
	end

	local oreFolder = oreAssets:FindFirstChild(oreName)
	local templates = oreFolder and oreFolder:GetChildren()
	if not templates or #templates == 0 then
		warn("OreUnloadEffects: нет кусочков руды в ReplicatedStorage.Assets.Ores." .. tostring(oreName))
		return
	end

	local visual = templates[math.random(1, #templates)]:Clone()
	prepareVisual(visual)

	local from = root.Position + randomOffset(SPAWN_SPREAD)
	local to = target.Position + randomOffset(TARGET_SPREAD)
	local control = (from + to) / 2 + Vector3.new(0, ARC_HEIGHT, 0)

	visual:PivotTo(CFrame.new(from))
	visual.Parent = workspace

	table.insert(flying, {
		visual = visual,
		t = 0,
		from = from,
		to = to,
		control = control,
		rotation = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28),
		spin = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8)),
	})

	if not flyConnection then
		flyConnection = RunService.Heartbeat:Connect(step)
	end
end

function OreUnloadEffects.Start() end

function OreUnloadEffects.Init() end

return OreUnloadEffects
