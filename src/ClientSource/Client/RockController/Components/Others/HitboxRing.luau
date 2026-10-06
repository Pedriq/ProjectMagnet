local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--[[
	HitboxRing — видимая граница хитбокса магнита (чисто визуально, локально).

	Это «радар»: тонкая СПЛОШНАЯ окружность радиуса серверного MagnetHitbox (Size.X / 2; сервер бьёт
	по кругу, см. PlayerMagnetHitboxManager:CollectTargets) и слабая заливка внутри. От игрока к границе
	расходятся мягкие кольца-волны (sonar) и гаснут у края — зона читается как «дальность действия».

	Намеренно НЕ похоже на площадки пресса (Unloading / Collect / Merge): там неподвижные детали-кнопки,
	которые утапливаются под ногами; здесь — ничего твёрдого и вращающегося, только лёгкая волна света.

	Рисуется одной прозрачной деталью на земле, а кольца — GUI на её верхней грани (SurfaceGui +
	круглые Frame с UIStroke): никаких штрихов/цилиндров, анимация — размер и прозрачность обводок.
	Центр — хитбокс (т.е. игрок), высота — земля под игроком (рейкаст вниз).

	Хитбокс пересоздаётся при прокачке ренджи / смене магнита — кольцо
	замечает новый радиус и перестраивается само.
]]

local HitboxRing = {}

---- Datas
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

local RING_COLOR = Theme.TealBright -- холодный бирюзовый: не совпадает с цветами площадок пресса
local FILL_COLOR = Theme.Teal
local RING_TRANSPARENCY = 0.5
local FILL_TRANSPARENCY = 0.93
local RING_WORLD_WIDTH = 0.14 -- толщина линии в studs (не зависит от радиуса)
local CANVAS = 512 -- px холста SurfaceGui
local MIN_STROKE_PX = 1.5

local WAVE_PERIOD = 2.8 -- секунд на одну волну
local WAVE_COUNT = 2 -- волн одновременно (равномерно сдвинуты по фазе)
local WAVE_START = 0.12 -- с какого размера (доля радиуса) волна стартует
local WAVE_EASE = 2.2 -- >1: быстрый старт, плавное затухание у границы
local WAVE_TRANSPARENCY = 0.4 -- прозрачность волны на старте (к краю растёт до 1)

local PART_HEIGHT = 0.05
local GROUND_LIFT = 0.05 -- над землёй, чтобы не мерцать (z-fighting)
local RAY_DEPTH = 30

---- State
local player = Players.LocalPlayer
local folder: Folder? = nil
local plate: Part? = nil
local ringStroke: UIStroke? = nil
local waves: { { Frame: Frame, Stroke: UIStroke } } = {}
local builtRadius = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = "HitboxRing"
	folder.Parent = workspace
	return folder :: Folder
end

local function circle(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function outline(frame: Frame, thickness: number, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = RING_COLOR
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return stroke
end

local function clear()
	if folder then
		folder:ClearAllChildren()
	end
	plate, ringStroke = nil, nil
	table.clear(waves)
	builtRadius = 0
end

local function build(radius: number)
	clear()
	local parent = ensureFolder()

	local part = Instance.new("Part")
	part.Name = "Radar"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1 -- GUI на грани рисуется и на невидимой детали
	part.Size = Vector3.new(radius * 2, PART_HEIGHT, radius * 2)
	part.Parent = parent
	plate = part

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Gui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS, CANVAS)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part

	-- толщина линии постоянна в мире: px холста на stud = CANVAS / диаметр
	local stroke = math.max(RING_WORLD_WIDTH * CANVAS / (radius * 2), MIN_STROKE_PX)

	-- слабая заливка зоны
	local disc = circle("Fill", gui)
	disc.BackgroundColor3 = FILL_COLOR
	disc.BackgroundTransparency = FILL_TRANSPARENCY

	-- граница хитбокса: тонкая сплошная линия
	local ring = circle("Ring", gui)
	ringStroke = outline(ring, stroke, RING_TRANSPARENCY)

	-- волны от центра к границе
	for i = 1, WAVE_COUNT do
		local frame = circle("Wave" .. i, gui)
		frame.Size = UDim2.fromScale(WAVE_START, WAVE_START)
		waves[i] = { Frame = frame, Stroke = outline(frame, stroke, 1) }
	end

	builtRadius = radius
end

local function hide()
	if builtRadius > 0 then
		clear()
	end
end

local function animate(now: number)
	local arrival = 0 -- 0..1: насколько близко самая дальняя волна к границе (кольцо слегка «вспыхивает»)
	for i, wave in ipairs(waves) do
		local phase = (now / WAVE_PERIOD + (i - 1) / WAVE_COUNT) % 1
		local eased = 1 - (1 - phase) ^ WAVE_EASE
		local size = WAVE_START + (1 - WAVE_START) * eased
		wave.Frame.Size = UDim2.fromScale(size, size)
		wave.Stroke.Transparency = WAVE_TRANSPARENCY + (1 - WAVE_TRANSPARENCY) * phase ^ 0.8
		arrival = math.max(arrival, math.clamp((phase - 0.8) / 0.2, 0, 1) * (1 - phase) * 5)
	end
	if ringStroke then
		ringStroke.Transparency = RING_TRANSPARENCY - 0.2 * arrival
	end
end

local function step()
	local character = player.Character
	local hitbox = character and character:FindFirstChild("MagnetHitbox") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hitbox or not root then
		hide()
		return
	end

	local radius = hitbox.Size.X / 2
	if math.abs(radius - builtRadius) > 1e-3 or not (folder and folder.Parent) or not (plate and plate.Parent) then
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

	if plate then
		plate.CFrame = CFrame.new(center.X, groundY + GROUND_LIFT + PART_HEIGHT / 2, center.Z)
	end
	animate(os.clock())
end

function HitboxRing.Start()
	RunService.RenderStepped:Connect(step)
end

function HitboxRing.Init() end

return HitboxRing
