local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--[[
	HitboxRing — видимая граница хитбокса магнита (чисто визуально, локально).

	Пунктирное кольцо на земле + еле заметная заливка, радиус = радиусу
	серверного MagnetHitbox (Size.X / 2; сервер бьёт по кругу, см.
	PlayerMagnetHitboxManager:CollectTargets). Центр — хитбокс (т.е. игрок),
	высота — земля под игроком (рейкаст вниз). Кольцо медленно вращается.

	Хитбокс пересоздаётся при прокачке ренджи / смене магнита — кольцо
	замечает новый радиус и перестраивается само.
]]

local HitboxRing = {}

---- Datas
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

local RING_COLOR = Theme.Electric
local FILL_COLOR = Theme.ElectricDeep
local SPIN_SPEED = math.rad(20) -- рад/сек
local DASH_PITCH = 1.6 -- studs окружности на один штрих (штрих + промежуток)
local DASH_FILL = 0.6 -- доля шага, занятая штрихом
local DASH_WIDTH = 0.22
local DASH_HEIGHT = 0.05
local MIN_DASHES, MAX_DASHES = 16, 96
local DASH_TRANSPARENCY = 0.15
local FILL_TRANSPARENCY = 0.88
local GROUND_LIFT = 0.04 -- над землёй, чтобы не мерцать (z-fighting)
local RAY_DEPTH = 30

---- State
local player = Players.LocalPlayer
local folder: Folder? = nil
local fill: BasePart? = nil
local dashes: { BasePart } = {}
local dashOffsets: { CFrame } = {}
local frameCFrames: { CFrame } = {}
local builtRadius = 0
local angle = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function makePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "HitboxRing"
	folder.Parent = workspace
	return folder :: Folder
end

local function clear()
	for _, dash in ipairs(dashes) do
		dash:Destroy()
	end
	table.clear(dashes)
	table.clear(dashOffsets)
	table.clear(frameCFrames)
	if fill then
		fill:Destroy()
		fill = nil
	end
	builtRadius = 0
end

-- Штрихи по окружности радиуса radius; число штрихов растёт с длиной кольца,
-- так что пунктир выглядит одинаково при любом рендже.
local function build(radius: number)
	clear()
	local parent = ensureFolder()

	local count = math.clamp(math.floor(2 * math.pi * radius / DASH_PITCH + 0.5), MIN_DASHES, MAX_DASHES)
	local dashLength = 2 * math.pi * radius / count * DASH_FILL

	for i = 1, count do
		local dash = makePart("Dash")
		dash.Material = Enum.Material.Neon
		dash.Color = RING_COLOR
		dash.Transparency = DASH_TRANSPARENCY
		-- штрих — касательная к кольцу: длина вдоль X, внешняя кромка ровно на радиусе
		dash.Size = Vector3.new(dashLength, DASH_HEIGHT, DASH_WIDTH)
		dash.Parent = parent

		local theta = (i - 1) / count * 2 * math.pi
		dashes[i] = dash
		dashOffsets[i] = CFrame.Angles(0, theta, 0) * CFrame.new(0, 0, -(radius - DASH_WIDTH / 2))
		frameCFrames[i] = CFrame.identity
	end

	local disc = makePart("Fill")
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = FILL_COLOR
	disc.Transparency = FILL_TRANSPARENCY
	-- ось цилиндра — X; кладём его плашмя (см. CFrame.Angles(0, 0, pi/2) в step)
	disc.Size = Vector3.new(DASH_HEIGHT / 2, radius * 2, radius * 2)
	disc.Parent = parent
	fill = disc

	builtRadius = radius
end

local function hide()
	if builtRadius > 0 then
		clear()
	end
end

local function step(dt: number)
	local character = player.Character
	local hitbox = character and character:FindFirstChild("MagnetHitbox") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hitbox or not root then
		hide()
		return
	end

	local radius = hitbox.Size.X / 2
	if math.abs(radius - builtRadius) > 1e-3 or not (folder and folder.Parent) then
		build(radius)
	end

	-- земля под игроком; без попадания (прыжок над пропастью) — уровень ног
	rayParams.FilterDescendantsInstances = { character, folder :: Folder, workspace:FindFirstChild("PlayersRock") }
	-- Луч видит только то, на чём персонаж реально может стоять: группа
	-- "Char_<id>" не коллайдится с чужими персонажами (PlayerCollisionInitializer),
	-- значит кольцо не «залезает» на игрока, в котором стоишь. RespectCanCollide
	-- заодно игнорирует неколлайдящиеся триггеры/зоны.
	rayParams.CollisionGroup = root.CollisionGroup
	rayParams.RespectCanCollide = true
	local center = hitbox.Position
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -RAY_DEPTH, 0), rayParams)
	local groundY
	if hit then
		groundY = hit.Position.Y
	else
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		groundY = root.Position.Y - root.Size.Y / 2 - (humanoid and humanoid.HipHeight or 2)
	end

	angle = (angle + SPIN_SPEED * dt) % (2 * math.pi)
	local base = CFrame.new(center.X, groundY + GROUND_LIFT + DASH_HEIGHT / 2, center.Z) * CFrame.Angles(0, angle, 0)

	for i, offset in ipairs(dashOffsets) do
		frameCFrames[i] = base * offset
	end
	workspace:BulkMoveTo(dashes, frameCFrames, Enum.BulkMoveMode.FireCFrameChanged)

	if fill then
		fill.CFrame = CFrame.new(center.X, groundY + GROUND_LIFT, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

function HitboxRing.Start()
	RunService.RenderStepped:Connect(step)
end

function HitboxRing.Init() end

return HitboxRing
