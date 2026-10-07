local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Knit = require(ReplicatedStorage.Packages.Knit)
local vide = require(ReplicatedStorage.Packages.Vide)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local juice = require(ReplicatedStorage.ClientSource.juice)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

--[[
	CheckpointController — локальный визуал чекпоинтов (см. CheckpointHandler).
	Проход: мягкая подсветка ворот, волна, искры, «+N ORE SAVED», звук (playPassEffect),
	затем чекпоинт плавно становится прозрачным только у этого игрока,
	на ресет (Entrance -> Save) возвращается стартовая прозрачность.

	Подсказка «Enter to Save Ore» (SurfaceGui в чекпоинте) видна только на
	СЛЕДУЮЩЕМ чекпоинте: порядок — по имени прямого ребёнка Workspace.Checkpoints
	(«1», «2», «3»… или «Checkpoint3»; парт или модель с партом). Следующий — с
	наименьшим номером больше самого дальнего пройденного. Текст ставится
	кодом: «Checkpoint: Enter to Save N Ore», N — руда в переноске (Data.carryCount).
]]
local CheckpointController = Knit.CreateController({
	Name = "CheckpointController",
})

--- Knit Services
local PlayerManagerService

---- Datas
local FOLDER_NAME = "Checkpoints"
local PASS_COLOR = Theme.Money -- чекпоинт активирован: «успех» (язык цвета UI.theme)
local ORE_COLOR = Theme.CopperBright -- руда, как в CarryMeter
-- Интенсивность эффекта прохода (больше прозрачность / меньше tint — тише)
local GATE_TINT = 0.45 -- насколько ворота окрашиваются в PASS_COLOR (0..1)
local GATE_GLOW_TRANSPARENCY = 0.55 -- до какой прозрачности ворота «проявляются»
local WAVE_TRANSPARENCY = 0.7 -- стартовая прозрачность волны

---- State
local originalTransparency = {} -- [BasePart] = Transparency до прохода
local hideTweens: { [BasePart]: Tween } = {} -- плавное исчезновение после вспышки
local folder: Instance? = nil
local highestPassed = 0 -- номер самого дальнего пройденного чекпоинта (0 — ни одного)

-- Число в имени: «3», «Checkpoint3», «Checkpoint 3».
local function numberIn(name: string): number?
	return tonumber(name) or tonumber(string.match(name, "%d+"))
end

-- Номер чекпоинта, к которому относится inst: первое число в именах по пути
-- от папки Checkpoints вниз к inst (модель «3» > парт «Checkpoint» и парт «3»).
local function indexOf(inst: Instance?): number?
	if not folder or not inst or not inst:IsDescendantOf(folder) then
		return nil
	end
	local chain = {}
	local current: Instance? = inst
	while current and current ~= folder do
		if current:IsA("BasePart") or current:IsA("Model") or current:IsA("Folder") then
			table.insert(chain, 1, current)
		end
		current = current.Parent
	end
	for _, node in ipairs(chain) do
		local n = numberIn(node.Name)
		if n then
			return n
		end
	end
	return nil
end


local GUI_NAME = "CheckpointTemplateGui"

local function formatCount(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Все чекпоинты: [номер] = парт. Если у номера есть парт с SurfaceGui — берём его,
-- иначе самый большой парт (его же слушает CheckpointHandler).
local function collectCheckpoints(): { [number]: BasePart }
	local result: { [number]: BasePart } = {}
	local hasGui: { [number]: boolean } = {}
	if not folder then
		return result
	end
	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("BasePart") then
			local index = indexOf(inst)
			if index then
				local withGui = inst:FindFirstChildWhichIsA("SurfaceGui") ~= nil
				local current = result[index]
				local better = current == nil
					or (withGui and not hasGui[index])
					or (withGui == (hasGui[index] or false) and inst.Size.Magnitude > current.Size.Magnitude)
				if better then
					result[index] = inst
					hasGui[index] = withGui
				end
			end
		end
	end
	return result
end

-- Номер следующего чекпоинта: наименьший номер > highestPassed.
local function nextIndex(checkpoints: { [number]: BasePart }): number?
	local best: number? = nil
	for index in pairs(checkpoints) do
		if index > highestPassed and (best == nil or index < best) then
			best = index
		end
	end
	return best
end

-- SurfaceGui-шаблон: ReplicatedStorage.Assets.Checkpoint.Template (сам SurfaceGui или парт/модель с ним).
local function findTemplate(): SurfaceGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local checkpoint = assets and assets:FindFirstChild("Checkpoint")
	local template = checkpoint and checkpoint:FindFirstChild("Template")
	if not template then
		return nil
	end
	if template:IsA("SurfaceGui") then
		return template
	end
	return template:FindFirstChildWhichIsA("SurfaceGui", true)
end

-- Динамические поля шаблона ищутся по имени (без учёта регистра, любая вложенность).
local CARRY_NAMES = { "carryvalue", "carry", "backpack", "backpackvalue", "backpackore", "carried" }
local SAVED_NAMES = { "savedvalue", "saved", "total", "totalvalue", "savedore", "totalsaved" }

local function findLabel(root: Instance, names: { string }): TextLabel?
	for _, wanted in ipairs(names) do
		for _, inst in ipairs(root:GetDescendants()) do
			if inst:IsA("TextLabel") and string.lower(inst.Name) == wanted then
				return inst
			end
		end
	end
	return nil
end

local activeGui: SurfaceGui? = nil
local activePart: BasePart? = nil
local warnedTemplate = false
local warnedLabels = false

local function clearActive()
	if activeGui then
		activeGui:Destroy()
	end
	activeGui, activePart = nil, nil
end

-- Всего сохранённой руды (profile.Ores), как в SavedOreMeter.
local function savedTotal(): number
	local total = 0
	for _, weight in pairs(Data.ores()) do
		total += tonumber(weight) or 0
	end
	return total
end

-- SurfaceGui из шаблона — только на следующем чекпоинте; значения берутся из Data.
local function refresh()
	if not folder then
		return
	end
	local checkpoints = collectCheckpoints()
	local target = nextIndex(checkpoints)
	local part = if target then checkpoints[target] else nil

	-- старые SurfaceGui чекпоинтов заменены шаблоном
	for _, gui in ipairs(folder:GetDescendants()) do
		if gui:IsA("SurfaceGui") then
			gui.Enabled = false
		end
	end

	if not part then
		clearActive()
		return
	end

	if activePart ~= part or not activeGui or not activeGui.Parent then
		clearActive()
		local template = findTemplate()
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not template or not playerGui then
			if not template and not warnedTemplate then
				warnedTemplate = true
				warn("[CheckpointController] нет ReplicatedStorage.Assets.Checkpoint.Template (SurfaceGui)")
			end
			return
		end
		local gui = template:Clone()
		gui.Name = GUI_NAME
		gui.Adornee = part
		gui.Enabled = true
		gui.Parent = playerGui
		activeGui, activePart = gui, part
	end

	local gui = activeGui :: SurfaceGui
	local carryLabel = findLabel(gui, CARRY_NAMES)
	local savedLabel = findLabel(gui, SAVED_NAMES)
	if carryLabel then
		carryLabel.Text = formatCount(Data.carryCount())
	end
	if savedLabel then
		savedLabel.Text = formatCount(savedTotal())
	end
	if not (carryLabel and savedLabel) and not warnedLabels then
		warnedLabels = true
		warn("[CheckpointController] в шаблоне не найдены TextLabel для руды в рюкзаке/всего сохранено (CarryValue / SavedValue)")
	end
end


-- Ворота мягко подсвечиваются и плавно гаснут (вместо мгновенного Transparency = 1).
function CheckpointController:Hide(part: BasePart)
	if originalTransparency[part] == nil then
		originalTransparency[part] = part.Transparency
	end
	local previous = hideTweens[part]
	if previous then
		previous:Cancel()
	end
	part.Transparency = math.min(part.Transparency, GATE_GLOW_TRANSPARENCY)
	local tween = TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.1), {
		Transparency = 1,
	})
	hideTweens[part] = tween
	tween:Play()
end

function CheckpointController:RestoreAll()
	for _, tween in pairs(hideTweens) do
		tween:Cancel()
	end
	table.clear(hideTweens)
	for part, transparency in pairs(originalTransparency) do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(originalTransparency)
end

-- Тихая расходящаяся «волна» в форме ворот: полупрозрачная копия-коробка
-- (не неон) чуть растёт и тает. Чисто визуально, локально, без коллизий/запросов.
local function shockwave(part: BasePart, growth: number)
	local wave = Instance.new("Part")
	wave.Name = "CheckpointWave"
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Material = Enum.Material.ForceField
	wave.Color = PASS_COLOR
	wave.Transparency = WAVE_TRANSPARENCY
	wave.Size = part.Size
	wave.CFrame = part.CFrame
	wave.Parent = workspace

	TweenService:Create(wave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = part.Size * growth,
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.55)
end

-- Поток руды: из ворот чекпоинта в рюкзак игрока. Маленькие неоновые кусочки летят по дуге
-- (квадратичная кривая Безье), с небольшой разбежкой старта; один Heartbeat на всю пачку,
-- без коллизий и запросов, отключается сам, когда последний кусочек долетел.
local FLY_MAX_PIECES = 8
local FLY_DURATION = 0.7
local FLY_STAGGER = 0.05
local FLY_SIZE = 0.45

local function flyOreToBackpack(part: BasePart, saved: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local count = math.clamp(math.ceil(math.sqrt(saved)), 3, FLY_MAX_PIECES)
	local pieces = {}
	for i = 1, count do
		local piece = Instance.new("Part")
		piece.Name = "CheckpointOre"
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CastShadow = false
		piece.Material = Enum.Material.Neon
		piece.Color = ORE_COLOR
		piece.Size = Vector3.one * FLY_SIZE
		piece.Transparency = 1
		piece.Parent = workspace
		table.insert(pieces, {
			Part = piece,
			Delay = (i - 1) * FLY_STAGGER,
			Start = part.Position
				+ Vector3.new((math.random() - 0.5) * part.Size.X * 0.6, (math.random() - 0.5) * part.Size.Y * 0.5, 0),
			Lift = 2.5 + math.random() * 2,
			Spin = math.random() * 6,
		})
	end

	local startTime = os.clock()
	local connection
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		local alive = 0
		-- рюкзак за спиной: чуть позади и выше корня персонажа (следим за игроком, он движется)
		local target = root.Position - root.CFrame.LookVector * 0.8 + Vector3.new(0, 0.6, 0)
		for _, p in ipairs(pieces) do
			local piece = p.Part
			if piece.Parent then
				local t = (elapsed - p.Delay) / FLY_DURATION
				if t >= 1 then
					piece:Destroy()
				else
					alive += 1
					if t > 0 then
						local e = t * t * (3 - 2 * t) -- smoothstep
						local control = (p.Start + target) / 2 + Vector3.new(0, p.Lift, 0)
						local a = p.Start:Lerp(control, e)
						local b = control:Lerp(target, e)
						piece.CFrame = CFrame.new(a:Lerp(b, e)) * CFrame.Angles(p.Spin * t, p.Spin * t * 0.7, 0)
						-- проявляется в начале, тает к концу — «впитывается» в рюкзак
						piece.Transparency = if t < 0.15 then 1 - t / 0.15 * 0.85 elseif t > 0.75 then 0.15 + (t - 0.75) / 0.25 * 0.85 else 0.15
						piece.Size = Vector3.one * FLY_SIZE * (1 - 0.5 * t)
					end
				end
			end
		end
		if alive == 0 or not root.Parent then
			connection:Disconnect()
			for _, p in ipairs(pieces) do
				p.Part:Destroy()
			end
		end
	end)
end

-- Эффект прохода чекпоинта (сдержанный): лёгкая подсветка ворот, одна мягкая
-- волна, немного искр, «+N ORE SAVED» и тихий звук. Без тряски камеры.
local function playPassEffect(part: BasePart, saved: number)
	local originalColor = part.Color
	part.Color = originalColor:Lerp(PASS_COLOR, GATE_TINT)
	task.delay(0.6, function()
		if part.Parent then
			part.Color = originalColor -- к ресету ворота вернутся в своём цвете
		end
	end)

	shockwave(part, 1.25)
	if saved > 0 then
		flyOreToBackpack(part, saved)
	end

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = root and root.Position or part.Position
	juice.burst(origin, PASS_COLOR, 10, { speed = 0.6, size = 0.6 })

	local text = if saved > 0 then `+{saved} ORE SAVED` else "CHECKPOINT"
	juice.worldText(origin + Vector3.new(0, 3, 0), text, if saved > 0 then ORE_COLOR else PASS_COLOR, {
		size = 0.9,
		rise = 1.5,
		time = 1,
		scatter = 0,
	})

	sfx.play("Checkpoint")
end

function CheckpointController:KnitStart()
	PlayerManagerService.CheckpointPassed:Connect(function(part, saved)
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			playPassEffect(part, tonumber(saved) or 0)
			self:Hide(part)
			local index = indexOf(part)
			if index and index > highestPassed then
				highestPassed = index
			end
			refresh()
		end
	end)

	PlayerManagerService.CheckpointsReset:Connect(function()
		self:RestoreAll()
		highestPassed = 0
		refresh()
	end)

	task.spawn(function()
		folder = workspace:WaitForChild(FOLDER_NAME, 30)
		if not folder then
			warn("[CheckpointController] не найден Workspace." .. FOLDER_NAME)
			return
		end
		-- новые/подгруженные стримингом чекпоинты сразу получают верное состояние
		folder.DescendantAdded:Connect(function(inst)
			if inst:IsA("SurfaceGui") or inst:IsA("BasePart") then
				task.defer(refresh)
			end
		end)
		-- количество руды на подсказке — реактивно от инвентаря переноски
		vide.root(function()
			vide.effect(function()
				Data.carryCount()
				Data.ores()
				vide.untrack(refresh)
			end)
		end)
	end)
end

function CheckpointController:KnitInit()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return CheckpointController
