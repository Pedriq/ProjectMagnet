local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

--[[
	tutorialGuide — мировая подсказка туториала: «дорожка» бегущих точек по земле от игрока к цели,
	маркер-стрелка с расстоянием над целью, подсветка (Highlight) цели.

	Всё создаётся локально на клиенте (Folder "TutorialGuide" в Workspace) — другие игроки
	ничего не видят. Игрока ничто не ведёт и не блокирует: детали без коллизий/запросов,
	можно идти любым путём.

	  Guide.set(position, adornee?) — показать/переставить подсказку на точку (и подсветить adornee)
	  Guide.clear()                 — спрятать (объекты остаются для повторного показа)
	  Guide.destroy()               — удалить совсем
]]
local Guide = {}

local COLOR = Theme.TutorialAccent
local ARRIVE_DISTANCE = 9 -- ближе — дорожку прячем (игрок уже на месте), остаётся только маркер
local FEET_OFFSET = Vector3.new(0, 2.6, 0) -- от HRP вниз до ног
local MARKER_HEIGHT = 5 -- маркер над точкой цели
local DOT_COUNT = 45 -- максимум точек дорожки
local DOT_SPACING = 3.5 -- шаг между точками, studs
local DOT_LIFT = 0.35 -- над землёй
local FLOW_SPEED = 1.6 -- точек в секунду «бегут» к цели

local folder: Folder? = nil
local endPart: Part? = nil
local marker: BillboardGui? = nil
local distanceLabel: TextLabel? = nil
local arrowLabel: TextLabel? = nil
local highlight: Highlight? = nil
local heartbeat: RBXScriptConnection? = nil
local dots: { Part } = {}
local rayParams: RaycastParams? = nil

local targetPosition: Vector3? = nil

local function makePart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = folder
	return part
end

local function makeDot(): Part
	local dot = makePart("Dot")
	dot.Shape = Enum.PartType.Cylinder
	dot.Material = Enum.Material.Neon
	dot.Color = COLOR
	dot.Transparency = 0
	dot.Size = Vector3.new(0.25, 1.6, 1.6) -- ось цилиндра — X; ниже кладём её вертикально
	return dot
end

local function textLabel(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = Enum.Font.GothamBlack
	label.TextSize = textSize
	label.TextColor3 = COLOR
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	return label
end

local function hideDots(from: number)
	for i = from, #dots do
		dots[i].Transparency = 1
	end
end

-- Дорожка: точки на равном шаге вдоль прямой игрок -> цель, прижатые к земле; «волна» размера бежит к цели.
local function updateTrail(rootPosition: Vector3, target: Vector3, distance: number, now: number)
	local start = rootPosition - FEET_OFFSET
	local length = distance - ARRIVE_DISTANCE
	if length <= DOT_SPACING then
		hideDots(1)
		return
	end

	local count = math.min(DOT_COUNT, math.floor(length / DOT_SPACING))
	local flow = (now * FLOW_SPEED) % 1
	local direction = (target - start).Unit
	local params = rayParams

	for i = 1, #dots do
		local dot = dots[i]
		if i > count then
			dot.Transparency = 1
		else
			local along = (i - 1 + flow) * DOT_SPACING + 3
			local point = start + direction * math.min(along, distance)
			local y = point.Y

			if params then
				local hit = Workspace:Raycast(point + Vector3.new(0, 5, 0), Vector3.new(0, -14, 0), params)
				if hit then
					y = hit.Position.Y
				end
			end

			-- волна: ближе к цели точка крупнее; у самого края дорожки — плавное появление/исчезновение
			local edge = math.clamp(math.min(i - 1 + flow, count - i + 1 - flow) / 2, 0, 1)
			local pulse = 0.75 + 0.35 * (math.sin(now * 5 - i * 0.7) * 0.5 + 0.5)
			local size = 1.6 * pulse * edge
			dot.Size = Vector3.new(0.25, size, size)
			dot.CFrame = CFrame.new(point.X, y + DOT_LIFT, point.Z) * CFrame.Angles(0, 0, math.pi / 2)
			dot.Transparency = 0
		end
	end
end

local function onHeartbeat()
	local finish = endPart
	if not targetPosition or not finish or not marker then
		return
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		hideDots(1)
		return
	end

	local now = os.clock()
	finish.Position = targetPosition

	local distance = (targetPosition - root.Position).Magnitude
	updateTrail(root.Position, targetPosition, distance, now)

	-- маркер плавно покачивается
	marker.StudsOffset = Vector3.new(0, MARKER_HEIGHT + math.sin(now * 3.2) * 0.5, 0)
	if distanceLabel then
		distanceLabel.Text = `{math.floor(distance + 0.5)}m`
	end
	if highlight then
		highlight.FillTransparency = 0.55 + 0.25 * (math.sin(now * 5) * 0.5 + 0.5)
	end
end

local function ensure()
	if folder and folder.Parent then
		return
	end

	folder = Instance.new("Folder")
	folder.Name = "TutorialGuide"
	folder.Parent = Workspace

	endPart = makePart("End")

	-- лучи вниз не должны упираться в игрока и в сами точки
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local rocks = Workspace:FindFirstChild("PlayersRock") -- хитбоксы руды (CanQuery) не должны поднимать точки
	params.FilterDescendantsInstances = { folder, rocks, Players.LocalPlayer.Character }
	rayParams = params
	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		params.FilterDescendantsInstances = { folder, rocks, character }
	end)

	dots = {}
	for i = 1, DOT_COUNT do
		dots[i] = makeDot()
	end
	hideDots(1)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Marker"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(90, 80)
	gui.MaxDistance = math.huge
	gui.Enabled = false
	gui.Adornee = endPart
	gui.Parent = folder
	marker = gui

	arrowLabel = textLabel("Arrow", UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 0), 46)
	arrowLabel.Text = "▼"
	arrowLabel.Parent = gui

	distanceLabel = textLabel("Distance", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 50), 20)
	distanceLabel.TextColor3 = Color3.new(1, 1, 1)
	distanceLabel.Parent = gui

	local h = Instance.new("Highlight")
	h.Name = "TargetHighlight"
	h.FillColor = COLOR
	h.FillTransparency = 0.6
	h.OutlineColor = COLOR
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = folder
	highlight = h

	heartbeat = RunService.Heartbeat:Connect(onHeartbeat)
end

function Guide.set(position: Vector3?, adornee: Instance?)
	if not position then
		Guide.clear()
		return
	end

	ensure()
	targetPosition = position
	if marker then
		marker.Enabled = true
	end
	if highlight and highlight.Adornee ~= adornee then
		highlight.Adornee = adornee
	end
end

function Guide.clear()
	targetPosition = nil
	hideDots(1)
	if marker then
		marker.Enabled = false
	end
	if highlight then
		highlight.Adornee = nil
	end
end

function Guide.destroy()
	targetPosition = nil
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
	end
	folder, endPart, marker, distanceLabel, arrowLabel, highlight, rayParams = nil, nil, nil, nil, nil, nil, nil
	dots = {}
end

return Guide
