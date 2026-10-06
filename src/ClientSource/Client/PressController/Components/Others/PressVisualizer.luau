local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

--[[
	PressVisualizer — ЛОКАЛЬНЫЙ визуал пресса: всё создаётся на клиенте, поэтому
	другие игроки этого не видят.

	  * руда выгружается разом: по несколько кусочков каждой руды летят с игрока
	    в PressInventory, остальные по одному падают в кучку; кусочки ложатся ровными слоями
	    (сетка, до PILE_MAX_HEIGHT); рама пресса (PressFrame) поднимается над кучкой;
	  * на крафт головка пресса бьёт по руде, из кучки исчезает
	    weight / PieceWeight кусочков этой руды, остальные оседают на свои ячейки,
	    из PressInventory «выдавливается» предмет, едет по Conveyor и падает в Sell;
	  * на Conveyor — ProximityPrompt «Press Queue», открывает окно очереди
	    (UI.screens.PressQueuePanel): прогресс руд, NEXT, кнопка X — убрать руду;
	  * кучка светится цветом самой редкой руды, удар головки — искры и тряска.

	Модели:
	  кусочки руды — ReplicatedStorage.Assets.Ores.<OreConfig.Model> (случайный ребёнок);
	  предметы     — ReplicatedStorage.Assets.Items (поиск по имени, в т.ч. в подпапках).
	Если модели нет — рисуется простой кубик цвета редкости.
]]
local PressVisualizer = {}

local PressFrame = require(script.Parent.PressFrame)
local juice = require(ReplicatedStorage.ClientSource.juice)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

local player = Players.LocalPlayer

---- Datas
local CONVEYOR_NAMES = { "Conveyor", "\u{421}onveyor" } -- второе — с кириллической «С»

local FLY_TIME = 0.8 -- полёт кусочка руды с игрока в пресс
local FLY_ARC = 5 -- высота дуги полёта
-- Выгрузка разом: в полёте показывается только несколько кусочков каждой руды,
-- остальные «достраивают» кучку (см. BUILD_* ниже).
local FLY_PIECES_PER_ORE = 6
local FLY_STAGGER = 0.1 -- пауза между вылетами кусочков
-- «Стройка» кучки: не долетевшие кусочки по одному падают в свои ячейки.
local BUILD_TIME = 1.2 -- за сколько достраивается кучка (сколько бы кусочков ни было)
local BUILD_MAX_STEP = 0.06 -- пауза между кусочками не больше этой (если их мало)
local BUILD_MIN_STEP = 1 / 180 -- ...и не меньше этой (потолок ~3 кусочка за кадр)
local MAX_ANIMATED_MOVERS = 60 -- сколько кусочков кучки плавно оседают после перестройки (остальные — сразу)
local MAX_ANIMATED_HOPS = 30 -- сколько кусочков «выпрыгивает» при удалении руды (остальные — сразу исчезают)
local DROP_TIME = 0.25 -- падение одного кусочка в ячейку
local DROP_HEIGHT = 2.5 -- с какой высоты над ячейкой он падает
-- Кучка руды: ровная сетка слоями над PressInventory (снизу вверх), до PILE_MAX_HEIGHT.
-- Что не влезло — не рисуется, но учитывается (hidden) и дорисуется, когда место освободится.
local PILE_CELL = 1.2 -- шаг сетки, studs (кусочек подгоняется под ячейку)
local PILE_PIECE_FILL = 0.95 -- доля ячейки, которую занимает кусочек
local PILE_LAYER_HEIGHT = 0.9 -- высота одного слоя, studs
local PILE_MAX_HEIGHT = 5 -- максимальная высота кучки, studs
-- С какого расстояния доступен ProximityPrompt «Press Queue» на Conveyor, studs
local QUEUE_PROMPT_DISTANCE = 20
local PILE_INSET = 0.1 -- отступ сетки от краёв PressInventory (доля размера)
local PILE_SETTLE_TIME = 0.25 -- кусочки «оседают» на новые места после крафта
local PIECE_FALLBACK_SIZE = 0.7
local PIECE_VANISH_TIME = 0.2

local ITEM_FOLDERS = { "Items", "Treasures" } -- папки моделей предметов в ReplicatedStorage.Assets
local ITEM_SIZE = 2 -- самая большая сторона предмета, studs
local SELL_SINK_TIME = 0.3 -- после падения предмет «проваливается» в Sell
local MONEY_POPUP_TIME = 1.2

-- ZoneDashedOutline у Unloading / Collect / Merge — декоративное кольцо зоны, медленно
-- крутится вокруг своей оси (детект игрока идёт по ZoneFloor, см. PressService).
local OUTLINE_SPIN_SPEED = math.rad(15) -- рад/сек

---- State
local press: Model? = nil
local visualsFolder: Folder? = nil
local outlineSpin: RBXScriptConnection? = nil
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
local queuePromptReady = false
local lastProgress: { [string]: number } = {}
local collectAnchor: BasePart? = nil
local collectLabel: TextLabel? = nil
local lastUnclaimed = "0"

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

-- Кусочек под размер ячейки. У готовых шаблонов (см. pieceTemplates) подгонка уже сделана и
-- помечена атрибутом Fitted, так что для клонов это мгновенный выход.
local function fitToCell(model: Model)
	if model:GetAttribute("Fitted") then
		return
	end
	local extents = model:GetExtentsSize()
	local biggest = math.max(extents.X, extents.Y, extents.Z)
	if biggest > 0 then
		safeScale(model, model:GetScale() * PILE_CELL * PILE_PIECE_FILL / biggest)
	end
	model:SetAttribute("Fitted", true)
end

-- Готовые шаблоны кусочков по руде: уже «чисто визуальные» (makeVisual) и подогнанные под ячейку.
-- Делаются ОДИН раз на руду; каждый новый кусочек — просто Clone() (раньше на каждый кусочек:
-- поиск в Assets, GetDescendants, GetExtentsSize, ScaleTo — это и давало просадки при merge).
local pieceTemplates: { [string]: { Model } } = {}

local function buildPieceTemplates(oreId: string): { Model }
	local ore = OreConfig.Get(oreId)
	local folder = assetsFolder("Ores")
	local variants = folder and ore and folder:FindFirstChild(ore.Model)

	local list: { Model } = {}
	if variants then
		for _, child in ipairs(variants:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				local model = toModel(child)
				if model then
					makeVisual(model)
					fitToCell(model)
					table.insert(list, model)
				end
			end
		end
	end

	if #list == 0 then
		local rarity = ore and ore.Rarity or oreId
		local model = fallbackModel(PIECE_FALLBACK_SIZE, RarityColors.get(rarity), Enum.Material.Slate)
		makeVisual(model)
		fitToCell(model)
		table.insert(list, model)
	end
	return list
end

local function createOrePiece(oreId: string): Model
	local list = pieceTemplates[oreId]
	if not list then
		list = buildPieceTemplates(oreId)
		pieceTemplates[oreId] = list
	end
	return list[math.random(1, #list)]:Clone()
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

local function createItem(itemName: string, rarity: string, payout: string): Model
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

	-- Якорь подписи — невидимая точка над центром модели. PrimaryPart у моделей
	-- часто не по центру, и подпись от него уезжала вбок. Якорь внутри модели,
	-- поэтому двигается и масштабируется вместе с ней (PivotTo / ScaleTo).
	local boxCFrame, boxSize = (model :: Model):GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.05
	anchor.CFrame = CFrame.new(boxCFrame.Position + Vector3.new(0, boxSize.Y / 2, 0))
	anchor.Parent = model

	-- подпись: имя предмета (цвет редкости), под ним — цена
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(4, 1.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.55)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = itemName
	label.TextColor3 = RarityColors.get(rarity)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Position = UDim2.fromScale(0, 0.55)
	priceLabel.Size = UDim2.fromScale(1, 0.45)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.FredokaOne
	priceLabel.TextScaled = true
	priceLabel.Text = "$" .. Format.short(payout)
	priceLabel.TextColor3 = Theme.Money
	priceLabel.TextStrokeTransparency = 0.3
	priceLabel.Parent = billboard
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

-- Исчезающие кусочки (сняты с кучки): раньше на КАЖДЫЙ кусочек — свой поток + ScaleTo каждый
-- кадр + Destroy, и при merge/крафте сотен кусочков это был скачок кадра. Теперь: один общий
-- цикл Heartbeat; плавно сжимаются максимум MAX_VANISH_ANIMATED кусочков, остальные сразу
-- скрываются и разрушаются порциями по DESTROY_PER_FRAME за кадр.
local MAX_VANISH_ANIMATED = 24
local DESTROY_PER_FRAME = 24
local vanishing: { { Model: Model, Base: number, T: number } } = {}
local destroyQueue: { Model } = {}
local vanishConn: RBXScriptConnection? = nil

local function pumpVanish(dt: number)
	local i = 1
	while i <= #vanishing do
		local v = vanishing[i]
		v.T += dt
		local alpha = math.min(v.T / PIECE_VANISH_TIME, 1)
		if v.Model.Parent and alpha < 1 then
			safeScale(v.Model, v.Base * (1 - alpha))
			i += 1
		else
			table.insert(destroyQueue, v.Model)
			vanishing[i] = vanishing[#vanishing] -- swap-remove
			vanishing[#vanishing] = nil
		end
	end

	for _ = 1, DESTROY_PER_FRAME do
		local model = table.remove(destroyQueue)
		if not model then
			break
		end
		model:Destroy()
	end

	if #vanishing == 0 and #destroyQueue == 0 and vanishConn then
		vanishConn:Disconnect()
		vanishConn = nil
	end
end

local function vanish(model: Model)
	if #vanishing < MAX_VANISH_ANIMATED then
		table.insert(vanishing, { Model = model, Base = model:GetScale(), T = 0 })
	else
		model.Parent = nil -- мгновенно пропадает с глаз, разрушится порцией позже
		table.insert(destroyQueue, model)
	end
	if not vanishConn then
		vanishConn = RunService.Heartbeat:Connect(pumpVanish)
	end
end

-- Свечение кучки: свет + искорки цвета самой редкой руды в прессе. Чем
-- реже руда, тем ярче — кучку Legendary видно издалека.
local GLOW_MIN_BRIGHTNESS = 0.6
local GLOW_BRIGHTNESS_PER_RARITY = 0.35
local glowAnchor: Part? = nil
local glowLight: PointLight? = nil
local glowSparkles: ParticleEmitter? = nil

local function ensureGlow(): boolean
	if glowAnchor and glowAnchor.Parent then
		return true
	end
	if not grid or not visualsFolder then
		return false
	end

	local anchor = Instance.new("Part")
	anchor.Name = "PileGlow"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	-- площадь кучки — искорки рождаются по всей её поверхности
	anchor.Size = Vector3.new(grid.Cols * PILE_CELL, 0.2, grid.Rows * PILE_CELL)
	anchor.CFrame = grid.Origin

	local light = Instance.new("PointLight")
	light.Range = 12
	light.Shadows = false
	light.Enabled = false
	light.Parent = anchor

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.SpreadAngle = Vector2.new(25, 25)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.1)
	sparkles.Rate = 0
	sparkles.Parent = anchor

	anchor.Parent = visualsFolder
	glowAnchor, glowLight, glowSparkles = anchor, light, sparkles
	return true
end

-- oreId -> номер руды в OreConfig.Order (вместо table.find в горячих циклах)
local ORE_INDEX: { [string]: number } = {}
for index, oreId in ipairs(OreConfig.Order) do
	ORE_INDEX[oreId] = index
end

local function updatePileGlow()
	if not ensureGlow() then
		return
	end

	local best = 0
	for _, entry in ipairs(pileList) do
		best = math.max(best, ORE_INDEX[entry.OreId] or 0)
	end
	for oreId, count in pairs(hidden) do
		if count > 0 then
			best = math.max(best, ORE_INDEX[oreId] or 0)
		end
	end

	local light, sparkles, anchor = glowLight :: PointLight, glowSparkles :: ParticleEmitter, glowAnchor :: Part
	if best == 0 then
		light.Enabled = false
		sparkles.Rate = 0
		return
	end

	local ore = OreConfig.Get(OreConfig.Order[best])
	local color = RarityColors.get(ore and ore.Rarity)
	light.Enabled = true
	light.Color = color
	light.Brightness = GLOW_MIN_BRIGHTNESS + (best - 1) * GLOW_BRIGHTNESS_PER_RARITY
	sparkles.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkles.Rate = 3 + best * 2
	-- поверхность свечения — верх кучки
	anchor.CFrame = (grid :: Grid).Origin + Vector3.new(0, pileTopY() - (grid :: Grid).Origin.Position.Y, 0)
end

-- Раме пресса — новый верх кучки.
local function updateFrame()
	if grid then
		PressFrame:SetPile(grid.Origin.Position.Y, pileTopY())
	end
	updatePileGlow()
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

-- Кусочек падает сверху в следующую ячейку, вырастая из маленького.
local function dropPiled(oreId: string)
	if not grid or not visualsFolder or #pileList >= grid.Capacity then
		return
	end
	local model = createOrePiece(oreId)
	fitToCell(model)
	local entry = appendEntry(oreId, model, true)

	model:PivotTo(entry.Target + Vector3.new(0, DROP_HEIGHT, 0))
	model.Parent = visualsFolder

	task.spawn(function()
		animate(DROP_TIME, function(alpha)
			if not model.Parent then
				return
			end
			-- цель читается каждый кадр: кучка могла перестроиться (крафт); масштаб не трогаем
			-- (ScaleTo на каждый кусочек каждый кадр — дорого, а падение читается и без него)
			model:PivotTo(entry.Target + Vector3.new(0, DROP_HEIGHT * (1 - alpha * alpha), 0))
		end)
		entry.Flying = false
		if model.Parent then
			model:PivotTo(entry.Target)
		end
	end)
end

local building = false -- идёт «стройка» кучки (см. _BuildHidden)

-- Скрытые кусочки по одному падают в свободные ячейки, пока есть место.
-- Вся стройка укладывается примерно в BUILD_TIME.
function PressVisualizer:_BuildHidden()
	if building or not grid then
		return
	end
	building = true

	task.spawn(function()
		local total = 0
		for _, count in pairs(hidden) do
			total += math.max(count, 0)
		end
		total = math.min(total, (grid :: Grid).Capacity - #pileList)
		-- не быстрее ~3 кусочков за кадр (BUILD_MIN_STEP): иначе сотни Clone за один кадр = просадка
		local step = math.max(math.min(BUILD_MAX_STEP, BUILD_TIME / math.max(total, 1)), BUILD_MIN_STEP)

		local debt = 0 -- накопленная пауза: если step меньше кадра, за кадр падает несколько
		while grid and #pileList < grid.Capacity do
			local nextOre = nil
			for _, oreId in ipairs(OreConfig.Order) do
				if (hidden[oreId] or 0) > 0 then
					nextOre = oreId
					break
				end
			end
			if not nextOre then
				break
			end

			hidden[nextOre] -= 1
			dropPiled(nextOre)

			debt += step
			if debt >= 1 / 60 then
				updateFrame()
				debt -= task.wait(debt)
			end
		end

		building = false
		updateFrame()
	end)
end

-- После удаления кусочков: все сдвигаются на свои ячейки (слои снова ровные),
-- свободные места сверху занимают скрытые кусочки.
function PressVisualizer:_Relayout()
	if not grid then
		return
	end

	-- Скрытые кусочки (не влезли в кучку) дорисовывает «стройка» порциями с анимацией падения —
	-- а не все сразу в одном кадре, как раньше.
	if not building then
		local anyHidden = false
		for _, count in pairs(hidden) do
			if count > 0 then
				anyHidden = true
				break
			end
		end
		if anyHidden and #pileList < grid.Capacity then
			self:_BuildHidden()
		end
	end

	-- Двигаются только те, у кого ячейка поменялась; плавно оседают первые MAX_ANIMATED_MOVERS,
	-- остальные просто ставятся на место одним PivotTo.
	local moving = {}
	for index, entry in ipairs(pileList) do
		local target = slotCFrame(index, entry.Yaw)
		if target ~= entry.Target then
			entry.Target = target
			if not entry.Flying then
				if #moving < MAX_ANIMATED_MOVERS then
					table.insert(moving, { Entry = entry, From = entry.Model:GetPivot() })
				else
					entry.Model:PivotTo(target)
				end
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

-- С игрока разом выгрузили всю руду (ores = map[oreId] = вес): каждой руды вылетает
-- до FLY_PIECES_PER_ORE кусочков, остальные по одному падают в кучку (_BuildHidden).
function PressVisualizer:OreUnloaded(ores: { [string]: number })
	if not press or not visualsFolder then
		return
	end
	self:_EnsureReady()

	local launches: { string } = {}
	for _, oreId in ipairs(OreConfig.Order) do
		local ore = OreConfig.Get(oreId)
		local weight = ores[oreId]
		if ore and weight and weight > 0 then
			local pieces = math.ceil(weight / ore.PieceWeight)
			if not grid then
				-- PressInventory ещё не пришла к клиенту: запоминаем, нарисуем, когда появится
				hidden[oreId] = (hidden[oreId] or 0) + pieces
			else
				local flying = math.min(pieces, FLY_PIECES_PER_ORE)
				for _ = 1, flying do
					table.insert(launches, oreId)
				end
				-- остальные сразу считаются скрытыми: если пресс начнёт крафт, пока
				-- кубики летят, он заберёт сначала их, а не летящие
				hidden[oreId] = (hidden[oreId] or 0) + pieces - flying
			end
		end
	end

	if #launches == 0 then
		return
	end

	-- как только долетел первый кубик — кучка начинает «достраиваться» остальными
	task.delay(FLY_TIME, function()
		self:_BuildHidden()
	end)

	task.spawn(function()
		for i, oreId in ipairs(launches) do
			self:_FlyPiece(oreId)
			if i < #launches then
				task.wait(FLY_STAGGER)
			end
		end
	end)
end

-- Кусочек руды летит с игрока в пресс и ложится в следующую ячейку.
function PressVisualizer:_FlyPiece(oreId: string)
	if not grid or not visualsFolder then
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
function PressVisualizer:_ConsumeFromPile(oreId: string, count: number, skipRelayout: boolean?)
	local fromHidden = math.min(hidden[oreId] or 0, count)
	hidden[oreId] = (hidden[oreId] or 0) - fromHidden
	count -= fromHidden

	if count > 0 then
		-- один проход сверху вниз: помечаем нужные, затем одним проходом уплотняем список
		-- (table.remove в цикле сдвигал бы хвост на КАЖДЫЙ удалённый кусочек — O(n·k))
		local drop: { [PileEntry]: boolean } = {}
		for index = #pileList, 1, -1 do
			if count <= 0 then
				break
			end
			local entry = pileList[index]
			if entry.OreId == oreId then
				drop[entry] = true
				vanish(entry.Model)
				count -= 1
			end
		end

		local write = 0
		for read = 1, #pileList do
			local entry = pileList[read]
			if not drop[entry] then
				write += 1
				pileList[write] = entry
			end
		end
		for index = #pileList, write + 1, -1 do
			pileList[index] = nil
		end
	end

	if not skipRelayout then
		self:_Relayout()
	end
end

-- Игрок убрал всю руду oreId из пресса (PressService.OreRemoved): все её кусочки
-- выпрыгивают из кучки и тают, остальные оседают на освободившиеся места.
function PressVisualizer:RemoveOre(oreId: string)
	hidden[oreId] = 0

	local color = RarityColors.get((OreConfig.Get(oreId) or {} :: any).Rarity)
	local removed = 0
	for index = #pileList, 1, -1 do
		local entry = pileList[index]
		if entry.OreId == oreId then
			table.remove(pileList, index)
			removed += 1
			local model = entry.Model
			if removed > MAX_ANIMATED_HOPS then
				vanish(model) -- сверх лимита: просто исчезает (общий пакетный цикл)
				continue
			end
			local from = model:GetPivot()
			local baseScale = model:GetScale()
			local hop = Vector3.new((math.random() * 2 - 1) * 2.5, 2 + math.random() * 1.5, (math.random() * 2 - 1) * 2.5)
			task.delay(removed * 0.01, function()
				animate(0.35, function(alpha)
					if model.Parent then
						-- подлёт вверх по параболе и сжатие
						local offset = Vector3.new(hop.X * alpha, hop.Y * math.sin(alpha * math.pi * 0.75), hop.Z * alpha)
						model:PivotTo(from + offset)
						safeScale(model, baseScale * (1 - alpha * 0.9))
					end
				end)
				model:Destroy()
			end)
		end
	end

	if grid then
		juice.burst(
			Vector3.new(grid.Origin.Position.X, pileTopY(), grid.Origin.Position.Z),
			color,
			math.clamp(removed, 8, 30),
			{ speed = 0.6 }
		)
	end
	self:_Relayout()
end

-- Ore Merge (PressService.OreMerged): кусочки сливаемых руд исчезают из кучки, а на их месте
-- появляются кусочки получившейся руды. steps — список { From, To, Groups, Consumed, Produced }.
-- Считаем ЧИСТОЕ изменение по каждой руде (при каскаде руда одновременно и получается, и
-- сливается дальше), сначала убираем лишнее — освобождая ячейки, потом достраиваем новое.
function PressVisualizer:ApplyMerge(steps: { any })
	local net: { [string]: number } = {}
	for _, step in ipairs(steps) do
		local from = OreConfig.Get(step.From)
		local to = OreConfig.Get(step.To)
		if from and to then
			net[step.From] = (net[step.From] or 0) - math.floor(step.Consumed / from.PieceWeight + 0.5)
			net[step.To] = (net[step.To] or 0) + math.floor(step.Produced / to.PieceWeight + 0.5)
		end
	end

	local added = false
	local removedAny = false
	local topColor: Color3? = nil
	for _, oreId in ipairs(OreConfig.Order) do
		local delta = net[oreId]
		if delta and delta < 0 then
			self:_ConsumeFromPile(oreId, -delta, true)
			removedAny = true
		end
	end
	if removedAny then
		self:_Relayout() -- ОДИН раз на весь merge
	end
	for _, oreId in ipairs(OreConfig.Order) do
		local delta = net[oreId]
		if delta and delta > 0 then
			hidden[oreId] = (hidden[oreId] or 0) + delta
			added = true
			topColor = RarityColors.get((OreConfig.Get(oreId) or {} :: any).Rarity)
		end
	end

	if added then
		self:_BuildHidden()
	end
	if grid and topColor then
		juice.burst(
			Vector3.new(grid.Origin.Position.X, pileTopY(), grid.Origin.Position.Z),
			topColor,
			16,
			{ speed = 0.8, size = 0.8 }
		)
	end
end

-- Руды oreId в прессе больше нет (вес 0), а в кучке ещё остались её кусочки — например, остаток
-- от крафта или рассинхрон: тихо убираем их, чтобы кучка отражала реальное содержимое.
function PressVisualizer:SyncOreGone(oreId: string)
	hidden[oreId] = 0
	local removedAny = false
	for index = #pileList, 1, -1 do
		local entry = pileList[index]
		if entry.OreId == oreId then
			table.remove(pileList, index)
			vanish(entry.Model)
			removedAny = true
		end
	end
	if removedAny then
		self:_Relayout()
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
	label.TextColor3 = Theme.Money
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

	-- удар: искры цвета руды, глухой «бум» и тряска, если игрок рядом с прессом
	if grid then
		local impact = Vector3.new(grid.Origin.Position.X, hitY, grid.Origin.Position.Z)
		juice.burst(impact, RarityColors.get(ore and ore.Rarity or oreId), 18, { speed = 0.9 })
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - impact).Magnitude < 45 then
			sfx.play("Smash", { pitch = 0.6, jitter = 0.05 })
			juice.shake(0.15)
		end
	end
	if ore then
		self:_ConsumeFromPile(oreId, math.ceil(weight / ore.PieceWeight))
	end

	local sell = findPart("Sell")
	if not inventory or not itemName or not rarity or not payout or not visualsFolder then
		return
	end

	local model = createItem(itemName, rarity, payout)
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

		-- 4) продано: деньги (сервер в этот же момент добавляет их в Unclaimed — забрать
		-- на Collect) и предмет проваливается в Sell
		moneyPopup(sellTop + Vector3.new(0, 1, 0), payout)
		animate(SELL_SINK_TIME, function(alpha)
			safeScale(model, baseScale * (1 - alpha))
			model:PivotTo(CFrame.new(sellTop:Lerp(sellCenter, alpha)) * facing)
		end)
		model:Destroy()
	end)
end

-- Руда в прессе изменилась: свечение кучки под самую редкую руду. Сам список
-- руд — в окне Press Queue (UI.screens.PressQueuePanel, Data.pressOres).
function PressVisualizer:UpdateProgress(ores: { [string]: number })
	lastProgress = ores
	updatePileGlow()
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

-- ProximityPrompt «Press Queue» на верхней грани Conveyor — открывает окно
-- очереди пресса. Якорь локальный (деталь может выгрузиться стримингом — якорь нет);
-- его имя "PressQueue" HUD сопоставляет с окном "press" (UI.baseStructures).
function PressVisualizer:_CreateQueuePrompt(conveyor: Instance)
	local cf, size = getBox(conveyor)

	local promptAnchor = Instance.new("Part")
	promptAnchor.Name = "PressQueue"
	promptAnchor.Anchored = true
	promptAnchor.CanCollide = false
	promptAnchor.CanQuery = false
	promptAnchor.CanTouch = false
	promptAnchor.Transparency = 1
	promptAnchor.Size = Vector3.one * 0.1
	promptAnchor.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2, 0))
	promptAnchor.Parent = visualsFolder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PressQueuePrompt"
	prompt.ActionText = "Press Queue"
	prompt.ObjectText = "Hydraulic Press"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = QUEUE_PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAnchor

	queuePromptReady = true
end

local function findCollect(): Instance?
	for _, name in ipairs(PressConfig.COLLECT_NAMES) do
		local found = findPart(name)
		if found then
			return found
		end
	end
	return nil
end

local function findMerge(): Instance?
	for _, name in ipairs(PressConfig.MERGE_NAMES) do
		local found = findPart(name)
		if found then
			return found
		end
	end
	return nil
end

local function findUnloading(): Instance?
	for _, name in ipairs(PressConfig.UNLOADING_NAMES) do
		local found = findPart(name)
		if found then
			return found
		end
	end
	return nil
end

-- Крутит ZoneDashedOutline вокруг своей оси на месте (Model — через PivotTo, BasePart — через
-- CFrame), не трогая позицию. Колец несколько (Unloading, Collect, Merge — у каждой зоны своё),
-- но ОДИН общий цикл Heartbeat на все. Кольцо, которое удалили (вместе с зоной), выпадает из
-- списка само; когда колец не осталось, цикл останавливается.
local spinners: { { Outline: Instance, Pivot: CFrame, Angle: number } } = {}
local spinning: { [Instance]: boolean } = {}

local function stepSpinners(deltaTime: number)
	local i = 1
	while i <= #spinners do
		local spinner = spinners[i]
		local outline = spinner.Outline
		if not outline.Parent then
			spinning[outline] = nil
			spinners[i] = spinners[#spinners] -- swap-remove
			spinners[#spinners] = nil
		else
			spinner.Angle = (spinner.Angle + OUTLINE_SPIN_SPEED * deltaTime) % (2 * math.pi)
			local spun = spinner.Pivot * CFrame.Angles(0, spinner.Angle, 0)
			if outline:IsA("Model") then
				(outline :: Model):PivotTo(spun)
			else
				(outline :: BasePart).CFrame = spun
			end
			i += 1
		end
	end

	if #spinners == 0 and outlineSpin then
		outlineSpin:Disconnect()
		outlineSpin = nil
	end
end

local function spinOutline(outline: Instance)
	if spinning[outline] then
		return
	end
	spinning[outline] = true
	local pivot = if outline:IsA("Model") then (outline :: Model):GetPivot() else (outline :: BasePart).CFrame
	table.insert(spinners, { Outline = outline, Pivot = pivot, Angle = 0 })
	if not outlineSpin then
		outlineSpin = RunService.Heartbeat:Connect(stepSpinners)
	end
end

-- Кольцо ZoneDashedOutline зоны (Unloading / Collect / Merge — у всех одна структура:
-- ZoneFloor для детекта + вращающееся ZoneDashedOutline) пускаем крутиться.
local function spinZoneOutline(zone: Instance?)
	local outline = zone and zone:FindFirstChild("ZoneDashedOutline")
	if outline and (outline:IsA("Model") or outline:IsA("BasePart")) then
		spinOutline(outline)
	end
end

-- Табличка над Collect: сколько денег ждёт сбора (profile.Press.Unclaimed).
function PressVisualizer:SetUnclaimed(amount: string)
	lastUnclaimed = amount -- табличка может появиться позже (стриминг) — покажет последнее
	if not collectLabel then
		return
	end

	collectLabel.Text = "$" .. Format.short(amount)
	collectLabel.Parent.Enabled = EtNum.me(amount, "0")
end

-- Игрок забрал деньги на Collect.
function PressVisualizer:MoneyCollected(amount: string)
	if collectAnchor then
		moneyPopup(collectAnchor.Position + Vector3.new(0, 1.5, 0), amount)
	end
end

-- Деталь, над которой висит табличка Collect: сама деталь (старый вариант) или ZoneFloor модели
-- (как у Unloading). nil — детали ещё не дошли до клиента (стриминг): табличку создадим позже,
-- а не посреди мира в (0, 3, 0), куда якорь попадал, пока у пустой модели не было ни одной детали.
local function collectAnchorPart(collect: Instance): BasePart?
	if collect:IsA("BasePart") then
		return collect
	end
	local floor = collect:FindFirstChild("ZoneFloor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	for _, d in ipairs(collect:GetDescendants()) do
		if d:IsA("BasePart") and not d:FindFirstAncestor("ZoneDashedOutline") and d.Name ~= "ZoneDashedOutline" then
			return d
		end
	end
	return nil
end

local function collectAnchorPosition(part: BasePart): Vector3
	return part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0)
end

function PressVisualizer:_CreateCollectBillboard(collect: Instance)
	local part = collectAnchorPart(collect)
	if not part then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "CollectAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(collectAnchorPosition(part))
	anchor.Parent = visualsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PressCollect"
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.fromScale(5, 1.4)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	billboard.Enabled = false
	billboard.Adornee = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Theme.Money
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard
	billboard.Parent = player:WaitForChild("PlayerGui")

	collectAnchor = anchor
	collectLabel = label
	self:SetUnclaimed(lastUnclaimed)
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

	if not queuePromptReady then
		local conveyor = findConveyor()
		if conveyor then
			self:_CreateQueuePrompt(conveyor)
		end
	end

	-- кольца всех трёх зон; вызывается раз в секунду, так что зоны, дошедшие по стримингу позже,
	-- подхватываются сами (spinOutline не дублирует уже вращающиеся)
	spinZoneOutline(findUnloading())
	spinZoneOutline(findCollect())
	spinZoneOutline(findMerge())

	-- Табличка с деньгами над Collect: создаём, когда у зоны появилась деталь; если якорь/табличку
	-- удалили (стриминг, пересоздание модели) — делаем заново; якорь каждую секунду сверяем с
	-- положением ZoneFloor (зона могла приехать/сместиться позже), а сумму выставляем заново.
	local collect = findCollect()
	if collect then
		if not collectLabel or not collectAnchor or not collectAnchor.Parent then
			if collectLabel and collectLabel.Parent then
				collectLabel.Parent:Destroy()
			end
			collectLabel, collectAnchor = nil, nil
			self:_CreateCollectBillboard(collect)
		else
			local part = collectAnchorPart(collect)
			if part then
				local wanted = collectAnchorPosition(part)
				if (collectAnchor.Position - wanted).Magnitude > 0.05 then
					collectAnchor.CFrame = CFrame.new(wanted)
				end
			end
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
