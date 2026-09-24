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

	  * кусочки руды летят с игрока в PressInventory и ложатся ровными слоями
	    (сетка, до PILE_MAX_HEIGHT); рама пресса (PressFrame) поднимается над кучкой;
	  * на крафт головка пресса бьёт по руде, из кучки исчезает
	    weight / PieceWeight кусочков этой руды, остальные оседают на свои ячейки,
	    из PressInventory «выдавливается» предмет, едет по Conveyor и падает в Sell;
	  * над PressInventory — табличка прогресса «руда: вес / WEIGHT_PER_ITEM».

	Модели:
	  кусочки руды — ReplicatedStorage.Assets.Ores.<OreConfig.Model> (случайный ребёнок);
	  предметы     — ReplicatedStorage.Assets.Items (поиск по имени, в т.ч. в подпапках).
	Если модели нет — рисуется простой кубик цвета редкости.
]]
local PressVisualizer = {}

local PressFrame = require(script.Parent.PressFrame)

local player = Players.LocalPlayer

---- Datas
local CONVEYOR_NAMES = { "Conveyor", "\u{421}onveyor" } -- второе — с кириллической «С»

local FLY_TIME = 0.5 -- полёт кусочка руды с игрока в пресс
local FLY_ARC = 4 -- высота дуги полёта
-- Кучка руды: ровная сетка слоями над PressInventory (снизу вверх), до PILE_MAX_HEIGHT.
-- Что не влезло — не рисуется, но учитывается (hidden) и дорисуется, когда место освободится.
local PILE_CELL = 1.2 -- шаг сетки, studs (кусочек подгоняется под ячейку)
local PILE_PIECE_FILL = 0.95 -- доля ячейки, которую занимает кусочек
local PILE_LAYER_HEIGHT = 0.9 -- высота одного слоя, studs
local PILE_MAX_HEIGHT = 5 -- максимальная высота кучки, studs
local PILE_INSET = 0.1 -- отступ сетки от краёв PressInventory (доля размера)
local PILE_SETTLE_TIME = 0.25 -- кусочки «оседают» на новые места после крафта
local PIECE_FALLBACK_SIZE = 0.7
local PIECE_VANISH_TIME = 0.2

local ITEM_FOLDERS = { "Items", "Treasures" } -- папки моделей предметов в ReplicatedStorage.Assets
local ITEM_SIZE = 2 -- самая большая сторона предмета, studs
local SELL_SINK_TIME = 0.3 -- после падения предмет «проваливается» в Sell
local MONEY_POPUP_TIME = 1.2

---- State
local press: Model? = nil
local visualsFolder: Folder? = nil
type PileEntry = {
	OreId: string,
	Model: Model,
	Yaw: CFrame, -- поворот кусочка на 0/90/180/270° — чтобы слои не выглядели клонами
	Target: CFrame, -- место в сетке (обновляется при перераскладке)
	Flying: boolean, -- ещё летит с игрока (сам догоняет Target)
}
type Grid = { Origin: CFrame, Cols: number, Rows: number, PerLayer: number, Capacity: number }

local pileList: { PileEntry } = {} -- порядок = номер ячейки (снизу вверх, слой за слоем)
local hidden: { [string]: number } = {} -- [oreId] = кусочков сверх вместимости (не нарисованы)
local grid: Grid? = nil
local progressLabel: TextLabel? = nil
local lastProgress: { [string]: number } = {}

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

-- Сетка кучки: основание — ВЕРХНЯЯ грань PressInventory (мировая Y), руда растёт
-- вверх. Без лучей: раньше луч вниз пролетал сквозь PressInventory без коллизии
-- и кучка строилась на земле. Деталь может быть повёрнута — берём её ось,
-- которая смотрит вверх, а две другие (выровненные по горизонтали) — оси сетки.
local function buildGrid(): Grid?
	local inventory = findPart("PressInventory")
	if not inventory then
		return nil
	end

	local cf, size = getBox(inventory)
	local axes = {
		{ Dir = cf.RightVector, Len = size.X },
		{ Dir = cf.UpVector, Len = size.Y },
		{ Dir = cf.LookVector, Len = size.Z },
	}
	table.sort(axes, function(a, b)
		return math.abs(a.Dir.Y) > math.abs(b.Dir.Y)
	end)
	local vertical, axisA, axisB = axes[1], axes[2], axes[3]

	local topY = cf.Position.Y + math.abs(vertical.Dir.Y) * vertical.Len / 2
	local flat = axisA.Dir * Vector3.new(1, 0, 1)
	local flatA = if flat.Magnitude > 0.01 then flat.Unit else Vector3.xAxis
	local base = Vector3.new(cf.Position.X, topY, cf.Position.Z)

	local cols = math.max(1, math.floor(axisA.Len * (1 - PILE_INSET * 2) / PILE_CELL))
	local rows = math.max(1, math.floor(axisB.Len * (1 - PILE_INSET * 2) / PILE_CELL))
	local layers = math.max(1, math.floor(PILE_MAX_HEIGHT / PILE_LAYER_HEIGHT))

	return {
		-- X сетки — вдоль axisA, Y — мировой верх, Z — вдоль axisB
		Origin = CFrame.fromMatrix(base, flatA, Vector3.yAxis),
		Cols = cols,
		Rows = rows,
		PerLayer = cols * rows,
		Capacity = cols * rows * layers,
	}
end

-- Ячейка №index (1..Capacity): слой за слоем, в слое — ряд за рядом.
local function slotCFrame(index: number, yaw: CFrame): CFrame
	local g = grid :: Grid
	local i = index - 1
	local layer = i // g.PerLayer
	local k = i % g.PerLayer
	local col, row = k % g.Cols, k // g.Cols
	local offset = Vector3.new(
		(col - (g.Cols - 1) / 2) * PILE_CELL,
		layer * PILE_LAYER_HEIGHT + PILE_LAYER_HEIGHT / 2,
		(row - (g.Rows - 1) / 2) * PILE_CELL
	)
	return g.Origin * CFrame.new(offset) * yaw
end

-- Верх кучки (мировой Y): по числу занятых слоёв.
local function pileTopY(): number
	if not grid then
		return 0
	end
	local layers = math.ceil(#pileList / grid.PerLayer)
	return grid.Origin.Position.Y + layers * PILE_LAYER_HEIGHT
end

local function randomYaw(): CFrame
	return CFrame.Angles(0, math.rad(90 * math.random(0, 3)), 0)
end

local function vanish(model: Model)
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

-- Кусочек под размер ячейки.
local function fitToCell(model: Model)
	local extents = model:GetExtentsSize()
	local biggest = math.max(extents.X, extents.Y, extents.Z)
	if biggest > 0 then
		safeScale(model, model:GetScale() * PILE_CELL * PILE_PIECE_FILL / biggest)
	end
end

-- Раме пресса — новый верх кучки.
local function updateFrame()
	if grid then
		PressFrame:SetPile(grid.Origin.Position.Y, pileTopY())
	end
end

-- Новая запись в конец кучки (следующая свободная ячейка).
local function appendEntry(oreId: string, model: Model, flying: boolean): PileEntry
	local yaw = randomYaw()
	local entry: PileEntry = {
		OreId = oreId,
		Model = model,
		Yaw = yaw,
		Target = slotCFrame(#pileList + 1, yaw),
		Flying = flying,
	}
	table.insert(pileList, entry)
	return entry
end

-- Кусочек сразу лежит в кучке (снапшот при старте / дорисовка скрытых).
local function spawnPiled(oreId: string): boolean
	if not grid or not visualsFolder or #pileList >= grid.Capacity then
		return false
	end
	local model = createOrePiece(oreId)
	fitToCell(model)
	local entry = appendEntry(oreId, model, false)
	model:PivotTo(entry.Target)
	model.Parent = visualsFolder
	return true
end

-- После удаления кусочков: все сдвигаются на свои ячейки (слои снова ровные),
-- свободные места сверху занимают скрытые кусочки.
function PressVisualizer:_Relayout()
	if not grid then
		return
	end

	for _, oreId in ipairs(OreConfig.Order) do
		while (hidden[oreId] or 0) > 0 and #pileList < grid.Capacity do
			hidden[oreId] -= 1
			spawnPiled(oreId)
		end
	end

	local moving = {}
	for index, entry in ipairs(pileList) do
		local target = slotCFrame(index, entry.Yaw)
		if target ~= entry.Target then
			entry.Target = target
			if not entry.Flying then
				table.insert(moving, { Entry = entry, From = entry.Model:GetPivot() })
			end
		end
	end

	if #moving > 0 then
		task.spawn(function()
			animate(PILE_SETTLE_TIME, function(alpha)
				local eased = 1 - (1 - alpha) ^ 2
				for _, m in ipairs(moving) do
					if m.Entry.Model.Parent and not m.Entry.Flying then
						m.Entry.Model:PivotTo(m.From:Lerp(m.Entry.Target, eased))
					end
				end
			end)
		end)
	end

	updateFrame()
end

-- Кусочек руды летит с игрока в пресс и ложится в следующую ячейку.
function PressVisualizer:OreUnloaded(oreId: string)
	if not press or not visualsFolder then
		return
	end
	self:_EnsureReady()
	if not grid then
		-- PressInventory ещё не пришла к клиенту: запоминаем, нарисуем, когда появится
		hidden[oreId] = (hidden[oreId] or 0) + 1
		return
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local model = createOrePiece(oreId)
	fitToCell(model)

	local entry: PileEntry? = nil
	if #pileList < grid.Capacity then
		entry = appendEntry(oreId, model, true)
		updateFrame()
	else
		-- кучка до потолка: кусочек долетает до верха и тает, учитываем как скрытый
		hidden[oreId] = (hidden[oreId] or 0) + 1
	end

	local topTarget = CFrame.new(grid.Origin.Position + Vector3.new(0, PILE_MAX_HEIGHT, 0))
	local function target(): CFrame
		return if entry then entry.Target else topTarget
	end

	local start = if root then (root :: BasePart).Position else target().Position + Vector3.new(0, 5, 0)
	local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

	model:PivotTo(CFrame.new(start))
	model.Parent = visualsFolder

	task.spawn(function()
		animate(FLY_TIME, function(alpha)
			if not model.Parent then
				return
			end
			-- цель читается каждый кадр: пока кусочек летит, кучка могла перестроиться
			local finish = target()
			local control = (start + finish.Position) / 2
				+ Vector3.new(0, FLY_ARC + (start - finish.Position).Magnitude * 0.2, 0)
			local position = bezier(start, control, finish.Position, alpha)
			model:PivotTo(CFrame.new(position) * finish.Rotation:Lerp(spin, 1 - alpha))
		end)

		if entry then
			entry.Flying = false
			if model.Parent then
				model:PivotTo(entry.Target)
			end
		else
			vanish(model)
		end
	end)
end

-- Убрать из кучки `count` кусочков руды oreId (ушли на предмет): сначала скрытые,
-- потом нарисованные — с верха кучки.
function PressVisualizer:_ConsumeFromPile(oreId: string, count: number)
	local fromHidden = math.min(hidden[oreId] or 0, count)
	hidden[oreId] = (hidden[oreId] or 0) - fromHidden
	count -= fromHidden

	for index = #pileList, 1, -1 do
		if count <= 0 then
			break
		end
		local entry = pileList[index]
		if entry.OreId == oreId then
			table.remove(pileList, index)
			vanish(entry.Model)
			count -= 1
		end
	end

	self:_Relayout()
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

	self:_EnsureReady()
	task.spawn(self._PlayCraft, self, oreId, weight, itemName, rarity, payout)
end

function PressVisualizer:_PlayCraft(oreId: string, weight: number, itemName: string?, rarity: string?, payout: string?)
	-- 0) удар: Middle + Press опускаются до руды, в момент удара кусочки уходят
	local inventory = findPart("PressInventory")
	local floorY = if grid then grid.Origin.Position.Y elseif inventory then topCenter(inventory).Y else 0
	local hitY = if #pileList > 0 then pileTopY() else floorY
	PressFrame:SlamAsync(hitY, PressConfig.SLAM_TIME)

	local ore = OreConfig.Get(oreId)
	if ore then
		self:_ConsumeFromPile(oreId, math.ceil(weight / ore.PieceWeight))
	end

	local sell = findPart("Sell")
	if not inventory or not itemName or not rarity or not payout or not visualsFolder then
		return
	end

	local model = createItem(itemName, rarity)
	local baseScale = model:GetScale()
	local halfHeight = model:GetExtentsSize().Y / 2

	-- предмет появляется на месте удара — над остатком кучки
	local startPos = if grid
		then Vector3.new(grid.Origin.Position.X, math.max(pileTopY(), floorY) + halfHeight, grid.Origin.Position.Z)
		else topCenter(inventory) + Vector3.new(0, halfHeight, 0)
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
	lastProgress = ores -- табличка может появиться позже (стриминг) — покажет последнее
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
				if not spawnPiled(oreId) then
					hidden[oreId] = (hidden[oreId] or 0) + 1
				end
			end
		end
	end
	updateFrame()
end

-- Табличка прогресса: на невидимом локальном якоре над PressInventory (сама деталь
-- может выгрузиться стримингом — якорь нет).
function PressVisualizer:_CreateProgressBillboard(inventory: Instance)
	local cf, size = getBox(inventory)

	local anchor = Instance.new("Part")
	anchor.Name = "ProgressAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + 3, 0))
	anchor.Parent = visualsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PressProgress"
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.fromScale(6, 2.5)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Enabled = false
	billboard.Adornee = anchor

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
	self:UpdateProgress(lastProgress)
end

local warnedFrame = false

-- Досоздать то, для чего уже появились детали. При StreamingEnabled у клиента
-- сначала есть только пустая модель HydraulicPress, а PressInventory / рама
-- приходят, когда игрок подходит ближе, — поэтому вызывается многократно.
function PressVisualizer:_EnsureReady()
	if not press or not visualsFolder then
		return
	end

	if not grid then
		grid = buildGrid()
		if grid then
			print(
				string.format(
					"[Press] сетка кучки: %dx%d, %d слоёв, вместимость %d кусочков, основание Y=%.2f",
					grid.Cols,
					grid.Rows,
					grid.Capacity // grid.PerLayer,
					grid.Capacity,
					grid.Origin.Position.Y
				)
			)
			-- руда, пришедшая до появления сетки, лежит в hidden — дорисуется здесь
			self:_Relayout()
		end
	end

	if not progressLabel then
		local inventory = findPart("PressInventory")
		if inventory then
			self:_CreateProgressBillboard(inventory)
		end
	end

	if grid and not PressFrame:IsReady() then
		local frame = findPart("Press")
		-- ошибка в раме не должна ломать остальной визуал пресса
		local ok, result = pcall(PressFrame.Setup, PressFrame, frame)
		if not ok then
			warn("[Press] рама пресса не запустилась:", result)
		elseif result then
			updateFrame()
		elseif frame and #frame:GetChildren() > 0 and not warnedFrame then
			warnedFrame = true
			warn("[Press] в HydraulicPress.Press нужны детали Left, Right, Middle, Press (Part/MeshPart)")
		end
	end
end

function PressVisualizer:Setup(pressModel: Model)
	press = pressModel

	local folder = Instance.new("Folder")
	folder.Name = "PressVisuals_Local"
	folder.Parent = workspace
	visualsFolder = folder

	self:_EnsureReady()
	task.spawn(function()
		while true do
			task.wait(1)
			self:_EnsureReady()
		end
	end)
end

function PressVisualizer.Start() end

function PressVisualizer.Init() end

return PressVisualizer
