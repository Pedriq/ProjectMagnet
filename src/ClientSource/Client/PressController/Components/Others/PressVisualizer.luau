local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

--[[
	PressVisualizer — ЛОКАЛЬНЫЙ визуал пресса: всё создаётся на клиенте, поэтому
	другие игроки этого не видят.

	  * кусочки руды летят с игрока в PressInventory и копятся там кучкой;
	  * на крафт из кучки исчезает WEIGHT_PER_ITEM / PieceWeight кусочков этой руды,
	    из PressInventory «выдавливается» предмет, едет по Conveyor и падает в Sell;
	  * над PressInventory — табличка прогресса «руда: вес / WEIGHT_PER_ITEM».

	Модели:
	  кусочки руды — ReplicatedStorage.Assets.Ores.<OreConfig.Model> (случайный ребёнок);
	  предметы     — ReplicatedStorage.Assets.Items (поиск по имени, в т.ч. в подпапках).
	Если модели нет — рисуется простой кубик цвета редкости.
]]
local PressVisualizer = {}

local player = Players.LocalPlayer

---- Datas
local CONVEYOR_NAMES = { "Conveyor", "\u{421}onveyor" } -- второе — с кириллической «С»

local FLY_TIME = 0.5 -- полёт кусочка руды с игрока в пресс
local FLY_ARC = 4 -- высота дуги полёта
-- Кучка загруженной руды в PressInventory. Пока выключена: кусочки долетают
-- до пресса и исчезают. true — вернуть кучку.
local SHOW_PILE = false
local PILE_MAX = 60 -- больше кусочков в кучке не рисуем
local PILE_INSET = 0.2 -- отступ кучки от краёв PressInventory (доля размера)
local PILE_LAYER_HEIGHT = 0.3 -- насколько кучка растёт вверх за каждые PILE_PER_LAYER кусочков
local PILE_PER_LAYER = 12
local PIECE_FALLBACK_SIZE = 0.7
local PIECE_VANISH_TIME = 0.2

local ITEM_FOLDERS = { "Items", "Treasures" } -- папки моделей предметов в ReplicatedStorage.Assets
local ITEM_SIZE = 2 -- самая большая сторона предмета, studs
local SELL_SINK_TIME = 0.3 -- после падения предмет «проваливается» в Sell
local MONEY_POPUP_TIME = 1.2

---- State
local press: Model? = nil
local visualsFolder: Folder? = nil
local pile: { [string]: { Model } } = {} -- [oreId] = кусочки в кучке
local pileCount = 0
local progressLabel: TextLabel? = nil

---- Helpers
local function getBox(inst: Instance): (CFrame, Vector3)
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	end
	return (inst :: Model):GetBoundingBox()
end

local function topCenter(inst: Instance): Vector3
	local cf, size = getBox(inst)
	return cf.Position + cf.UpVector * (size.Y / 2)
end

local function findPart(name: string): Instance?
	return press and press:FindFirstChild(name)
end

local function findConveyor(): Instance?
	for _, name in ipairs(CONVEYOR_NAMES) do
		local found = findPart(name)
		if found then
			return found
		end
	end
	return nil
end

-- Прогнать step(alpha 0..1) за duration секунд (yield).
local function animate(duration: number, step: (number) -> ())
	local t = 0
	while t < duration do
		t += RunService.Heartbeat:Wait()
		step(math.min(t / duration, 1))
	end
	step(1)
end

local function bezier(a: Vector3, control: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(control, t):Lerp(control:Lerp(b, t), t)
end

-- Сделать модель чисто визуальной: без физики/коллизий/хитов.
local function makeVisual(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
end

-- Клон шаблона (BasePart или Model) — всегда Model, чтобы двигать через PivotTo/ScaleTo.
local function toModel(template: Instance): Model?
	if template:IsA("Model") then
		local clone = template:Clone()
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		return if clone.PrimaryPart then clone else nil
	elseif template:IsA("BasePart") then
		local model = Instance.new("Model")
		local part = template:Clone()
		part.Parent = model
		model.PrimaryPart = part
		return model
	end
	return nil
end

local function fallbackModel(size: number, color: Color3, material: Enum.Material): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Size = Vector3.one * size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function safeScale(model: Model, scale: number)
	pcall(model.ScaleTo, model, math.max(scale, 0.05))
end

local function assetsFolder(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild(name)
end

local function createOrePiece(oreId: string): Model
	local ore = OreConfig.Get(oreId)
	local folder = assetsFolder("Ores")
	local variants = folder and ore and folder:FindFirstChild(ore.Model)

	local model: Model? = nil
	if variants then
		local options = {}
		for _, child in ipairs(variants:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				table.insert(options, child)
			end
		end
		if #options > 0 then
			model = toModel(options[math.random(1, #options)])
		end
	end

	if not model then
		local rarity = ore and ore.Rarity or oreId
		model = fallbackModel(PIECE_FALLBACK_SIZE, RarityColors.get(rarity), Enum.Material.Slate)
	end

	makeVisual(model :: Model)
	return model :: Model
end

local warnedMissing: { [string]: boolean } = {}

-- Модель предмета: ищется по имени во всей папке Assets.Items (можно раскладывать
-- по подпапкам редкостей), запасной вариант — старая Assets.Treasures.
local function findItemTemplate(itemName: string): Instance?
	for _, folderName in ipairs(ITEM_FOLDERS) do
		local folder = assetsFolder(folderName)
		local template = folder and folder:FindFirstChild(itemName, true)
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			return template
		end
	end

	if not warnedMissing[itemName] then
		warnedMissing[itemName] = true
		warn("[Press] нет модели предмета «" .. itemName .. "» в ReplicatedStorage.Assets.Items — рисую кубик")
	end
	return nil
end

local function createItem(itemName: string, rarity: string): Model
	local template = findItemTemplate(itemName)
	local model = template and toModel(template)

	if model then
		local extents = model:GetExtentsSize()
		local biggest = math.max(extents.X, extents.Y, extents.Z)
		if biggest > 0 then
			safeScale(model, model:GetScale() * ITEM_SIZE / biggest)
		end
	else
		model = fallbackModel(ITEM_SIZE * 0.75, RarityColors.get(rarity), Enum.Material.Neon)
	end

	makeVisual(model :: Model)

	-- подпись с именем предмета (цвет редкости)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(4, 0.8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, ITEM_SIZE * 0.9, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = (model :: Model).PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = itemName
	label.TextColor3 = RarityColors.get(rarity)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	billboard.Parent = model

	return model :: Model
end

-- Где лежит следующий кусочек кучки: луч сверху вниз в случайную точку
-- PressInventory — попадёт в дно/пол пресса (невидимые зоны без коллизии пропускаются).
function PressVisualizer:_NextPileCFrame(pieceHeight: number): CFrame
	local inventory = findPart("PressInventory")
	if not inventory then
		return CFrame.new()
	end

	local cf, size = getBox(inventory)
	local half = size * (0.5 - PILE_INSET)
	local offset = Vector3.new((math.random() * 2 - 1) * half.X, 0, (math.random() * 2 - 1) * half.Z)
	local top = cf:PointToWorldSpace(Vector3.new(offset.X, size.Y / 2 + 0.5, offset.Z))

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { visualsFolder, player.Character }
	params.RespectCanCollide = true

	local hit = workspace:Raycast(top, -cf.UpVector * (size.Y + 20), params)
	local floor = if hit then hit.Position else top - cf.UpVector * 0.5
	local layer = math.floor(pileCount / PILE_PER_LAYER)
	local position = floor + cf.UpVector * (pieceHeight / 2 + layer * PILE_LAYER_HEIGHT)

	return CFrame.new(position) * CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, 0)
end

function PressVisualizer:_AddToPile(oreId: string, model: Model)
	pile[oreId] = pile[oreId] or {}
	table.insert(pile[oreId], model)
	pileCount += 1
end

-- Кусочек сразу лежит в кучке (снапшот при старте).
function PressVisualizer:_SpawnPiled(oreId: string)
	if not SHOW_PILE or pileCount >= PILE_MAX or not visualsFolder then
		return
	end
	local model = createOrePiece(oreId)
	model:PivotTo(self:_NextPileCFrame(model:GetExtentsSize().Y))
	model.Parent = visualsFolder
	self:_AddToPile(oreId, model)
end

-- Кусочек руды летит с игрока в пресс.
function PressVisualizer:OreUnloaded(oreId: string)
	if not press or not visualsFolder then
		return
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local model = createOrePiece(oreId)
	local target = self:_NextPileCFrame(model:GetExtentsSize().Y)
	local start = if root then (root :: BasePart).Position else target.Position + Vector3.new(0, 5, 0)

	-- место в кучке занимаем сразу, чтобы следующие кусочки ложились выше
	local toPile = SHOW_PILE and pileCount < PILE_MAX
	if toPile then
		self:_AddToPile(oreId, model)
	end

	local control = (start + target.Position) / 2 + Vector3.new(0, FLY_ARC + (start - target.Position).Magnitude * 0.2, 0)
	local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

	model:PivotTo(CFrame.new(start))
	model.Parent = visualsFolder

	task.spawn(function()
		animate(FLY_TIME, function(alpha)
			if not model.Parent then
				return
			end
			local position = bezier(start, control, target.Position, alpha)
			local rotation = target.Rotation:Lerp(spin, 1 - alpha)
			model:PivotTo(CFrame.new(position) * rotation)
		end)

		if not toPile then
			-- в кучку не попал — тает в прессе
			local baseScale = model:GetScale()
			animate(PIECE_VANISH_TIME, function(alpha)
				if model.Parent then
					safeScale(model, baseScale * (1 - alpha))
				end
			end)
			model:Destroy()
		end
	end)
end

-- Убрать из кучки `count` кусочков руды oreId (ушли на предмет).
function PressVisualizer:_ConsumeFromPile(oreId: string, count: number)
	local pieces = pile[oreId]
	if not pieces then
		return
	end

	for _ = 1, math.min(count, #pieces) do
		local model = table.remove(pieces)
		pileCount -= 1
		task.spawn(function()
			local baseScale = model:GetScale()
			animate(PIECE_VANISH_TIME, function(alpha)
				if model.Parent then
					safeScale(model, baseScale * (1 - alpha))
				end
			end)
			model:Destroy()
		end)
	end
end

-- Точки конвейера: начало (ближе к PressInventory) и конец (ближе к Sell).
local function conveyorPath(itemHalfHeight: number): (Vector3?, Vector3?)
	local conveyor = findConveyor()
	if not conveyor then
		return nil, nil
	end

	local cf, size = getBox(conveyor)
	local axis, half
	if size.X >= size.Z then
		axis, half = cf.RightVector, size.X / 2
	else
		axis, half = cf.LookVector, size.Z / 2
	end
	half = math.max(half - math.min(1, half * 0.1), 0)

	local top = cf.Position + cf.UpVector * (size.Y / 2 + itemHalfHeight)
	local a, b = top + axis * half, top - axis * half

	local sell = findPart("Sell")
	if sell then
		local sellPos = getBox(sell).Position
		if (a - sellPos).Magnitude < (b - sellPos).Magnitude then
			a, b = b, a
		end
	else
		local inventory = findPart("PressInventory")
		if inventory and (b - getBox(inventory).Position).Magnitude < (a - getBox(inventory).Position).Magnitude then
			a, b = b, a
		end
	end
	return a, b
end

local function moneyPopup(position: Vector3, payout: string)
	if not visualsFolder then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = position
	anchor.Parent = visualsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(5, 1.4)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "+$" .. Format.short(payout)
	label.TextColor3 = Color3.fromRGB(60, 255, 90)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = anchor

	task.spawn(function()
		animate(MONEY_POPUP_TIME, function(alpha)
			anchor.Position = position + Vector3.new(0, alpha * 3, 0)
			label.TextTransparency = math.max(alpha * 2 - 1, 0)
			label.TextStrokeTransparency = 0.2 + 0.8 * math.max(alpha * 2 - 1, 0)
		end)
		anchor:Destroy()
	end)
end

-- Пресс сделал предмет: кучка уменьшается, предмет едет по конвейеру и падает в Sell.
-- Тайминги — из PressConfig (деньги сервер начисляет через SELL_DELAY).
function PressVisualizer:ItemCrafted(oreId: string, weight: number, itemName: string?, rarity: string?, payout: string?)
	if not press or not visualsFolder then
		return
	end

	local ore = OreConfig.Get(oreId)
	if ore then
		self:_ConsumeFromPile(oreId, math.ceil(weight / ore.PieceWeight))
	end

	local inventory = findPart("PressInventory")
	local sell = findPart("Sell")
	if not inventory or not itemName or not rarity or not payout then
		return
	end

	local model = createItem(itemName, rarity)
	local baseScale = model:GetScale()
	local halfHeight = model:GetExtentsSize().Y / 2

	local startPos = topCenter(inventory) + Vector3.new(0, halfHeight, 0)
	local convStart, convEnd = conveyorPath(halfHeight)
	convStart = convStart or startPos
	convEnd = convEnd or convStart
	local sellTop = if sell then topCenter(sell) + Vector3.new(0, halfHeight, 0) else convEnd :: Vector3
	local sellCenter = if sell then getBox(sell).Position else sellTop

	local direction = ((convEnd :: Vector3) - (convStart :: Vector3)) * Vector3.new(1, 0, 1)
	local facing = if direction.Magnitude > 0.01
		then CFrame.lookAt(Vector3.zero, direction.Unit).Rotation
		else CFrame.identity

	safeScale(model, baseScale * 0.1)
	model:PivotTo(CFrame.new(startPos) * facing)
	model.Parent = visualsFolder

	task.spawn(function()
		-- 1) выдавливание из пресса: растёт и подпрыгивает
		animate(PressConfig.PRESS_TIME, function(alpha)
			safeScale(model, baseScale * (0.1 + 0.9 * alpha))
			local bounce = math.sin(alpha * math.pi) * 1.5
			model:PivotTo(CFrame.new(startPos + Vector3.new(0, bounce, 0)) * facing)
		end)

		-- 2) по конвейеру: PressInventory -> начало -> конец (скорость постоянная)
		local points = { startPos, convStart :: Vector3, convEnd :: Vector3 }
		local lengths, total = {}, 0
		for i = 1, #points - 1 do
			lengths[i] = (points[i + 1] - points[i]).Magnitude
			total += lengths[i]
		end
		animate(PressConfig.CONVEYOR_TIME, function(alpha)
			local distance = alpha * total
			local position = points[#points]
			for i = 1, #lengths do
				if distance <= lengths[i] or i == #lengths then
					local t = if lengths[i] > 0 then math.clamp(distance / lengths[i], 0, 1) else 1
					position = points[i]:Lerp(points[i + 1], t)
					break
				end
				distance -= lengths[i]
			end
			model:PivotTo(CFrame.new(position) * facing)
		end)

		-- 3) падение с конца конвейера в Sell (с ускорением, по дуге вперёд)
		local fallStart = convEnd :: Vector3
		local control = fallStart:Lerp(sellTop, 0.5) + Vector3.new(0, 1.5, 0)
		animate(PressConfig.FALL_TIME, function(alpha)
			model:PivotTo(CFrame.new(bezier(fallStart, control, sellTop, alpha * alpha)) * facing)
		end)

		-- 4) продано: деньги (сервер начисляет в этот же момент) и предмет проваливается в Sell
		moneyPopup(sellTop + Vector3.new(0, 1, 0), payout)
		animate(SELL_SINK_TIME, function(alpha)
			safeScale(model, baseScale * (1 - alpha))
			model:PivotTo(CFrame.new(sellTop:Lerp(sellCenter, alpha)) * facing)
		end)
		model:Destroy()
	end)
end

-- Табличка прогресса над PressInventory: «руда: вес / WEIGHT_PER_ITEM».
function PressVisualizer:UpdateProgress(ores: { [string]: number })
	if not progressLabel then
		return
	end

	local lines = {}
	for _, oreId in ipairs(OreConfig.Order) do
		local weight = ores[oreId]
		if weight and weight > 0 then
			local ore = OreConfig.Get(oreId)
			local color = RarityColors.get(ore and ore.Rarity or oreId):ToHex()
			-- сколько предметов уже в очереди на крафт + прогресс следующего
			local queued = math.floor(weight / PressConfig.WEIGHT_PER_ITEM)
			local line = string.format(
				'<font color="#%s">%s</font>: %d / %d',
				color,
				oreId,
				math.floor(weight % PressConfig.WEIGHT_PER_ITEM),
				PressConfig.WEIGHT_PER_ITEM
			)
			if queued > 0 then
				line ..= string.format("  (x%d)", queued)
			end
			table.insert(lines, line)
		end
	end
	progressLabel.Text = table.concat(lines, "\n")
	progressLabel.Parent.Enabled = #lines > 0
end

-- Кучка по снапшоту руды в прессе (вход в игру).
function PressVisualizer:BuildPile(ores: { [string]: number })
	for _, oreId in ipairs(OreConfig.Order) do
		local ore = OreConfig.Get(oreId)
		local weight = ores[oreId]
		if ore and weight and weight > 0 then
			for _ = 1, math.floor(weight / ore.PieceWeight) do
				self:_SpawnPiled(oreId)
			end
		end
	end
end

function PressVisualizer:Setup(pressModel: Model)
	press = pressModel

	local folder = Instance.new("Folder")
	folder.Name = "PressVisuals_Local"
	folder.Parent = workspace
	visualsFolder = folder

	local inventory = findPart("PressInventory")
	if inventory then
		local _, size = getBox(inventory)
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PressProgress"
		billboard.ResetOnSpawn = false
		billboard.Size = UDim2.fromScale(6, 2.5)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 3, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 80
		billboard.Enabled = false
		billboard.Adornee = if inventory:IsA("BasePart") then inventory else (inventory :: Model).PrimaryPart
		if not billboard.Adornee then
			-- Model без PrimaryPart: невидимый якорь в центре
			local anchor = Instance.new("Part")
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Transparency = 1
			anchor.Size = Vector3.one * 0.1
			anchor.CFrame = getBox(inventory)
			anchor.Parent = folder
			billboard.Adornee = anchor
		end

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.RichText = true
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = billboard
		billboard.Parent = player:WaitForChild("PlayerGui")
		progressLabel = label
	end
end

function PressVisualizer.Start() end

function PressVisualizer.Init() end

return PressVisualizer
