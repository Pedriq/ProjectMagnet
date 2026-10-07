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

-- Все SurfaceGui чекпоинтов: внутри папки и в PlayerGui с Adornee на чекпоинт.
local function collectGuis(): { [SurfaceGui]: number }
	local result = {}
	if not folder then
		return result
	end
	for _, gui in ipairs(folder:GetDescendants()) do
		if gui:IsA("SurfaceGui") then
			local index = indexOf(gui.Adornee or gui.Parent)
			if index then
				result[gui] = index
			end
		end
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in ipairs(playerGui:GetDescendants()) do
			if gui:IsA("SurfaceGui") and gui.Adornee then
				local index = indexOf(gui.Adornee)
				if index then
					result[gui] = index
				end
			end
		end
	end
	return result
end

-- Номер следующего чекпоинта: наименьший номер > highestPassed.
local function nextIndex(guis: { [SurfaceGui]: number }): number?
	local best: number? = nil
	for _, index in pairs(guis) do
		if index > highestPassed and (best == nil or index < best) then
			best = index
		end
	end
	return best
end

-- Подсказка на чекпоинте: CHECKPOINT / [рюкзак] N ▶ [руда] M / TOUCH TO SAVE ORE.
-- N — руда в рюкзаке (Data.carryCount), M — всего сохранено (Data.ores). Иконки рюкзака/руды — как в HUD (CarryMeter /
-- SavedOreMeter).
local INFO_NAME = "CheckpointInfo"
local BACKPACK_ICON = "rbxassetid://15507675979"
local ORE_ICON = "rbxassetid://75588119022884"
local ARROW_COLOR = PASS_COLOR

local function formatCount(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function addStroke(inst: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = Color3.new(0, 0, 0)
	s.Parent = inst
end

-- Один раз строит панель поверх SurfaceGui; всё в масштабе, поэтому одинаково на любой поверхности.
-- Ширина текста в «высотах шрифта» (Size = 1): по реальным метрикам шрифта, чтобы строки
-- собирались плотно и точно по центру (TextScaled сам ширину не ужимает).
local TextService = game:GetService("TextService")
local FONT = Font.fromEnum(Enum.Font.GothamBlack)
local widthCache: { [string]: number } = {}

local function widthRatio(text: string): number
	local cached = widthCache[text]
	if cached then
		return cached
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = FONT
	params.Size = 100
	params.Width = 10000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	local ratio = if ok then bounds.X / 100 else #text * 0.75
	widthCache[text] = ratio
	return ratio
end

--[[
	Композиция считается по метрикам и подгоняется ровно под свой контент (никаких «полей»):
	высоты строк — это высота ЗАГЛАВНЫХ букв (кегль = строка / CAP), поэтому строки идут вплотную.
	Единицы — доли высоты композиции H; ширина композиции W = max(ширина строк).
	Композиция вписывается в поверхность чекпоинта по меньшей стороне (FitWithinMaxSize).
]]
local CAP = 0.74 -- высота заглавных GothamBlack / кегль
-- высоты строк (заглавные буквы заполняют строку целиком)
local PITCH = { Title = 0.34, Flow = 0.26, Hint = 0.2 }
local AMOUNT_PITCH = 0.22 -- числа рядом с иконками рюкзака и руды
local GAP = 0.04 -- между строками
local NOMINAL_AMOUNT = "1,000" -- ширина числа, под которую считается композиция (длиннее — сожмётся)
local ARROW_W = 0.17 -- ширина стрелки
local SPACE = 0.045 -- зазор между элементами цепочки

local function fontSize(pitch: number): number -- кегль, при котором заглавные занимают всю строку
	return pitch / CAP
end

local function addText(parent: Instance, props: { [string]: any }, strokeThickness: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	l.Parent = parent
	addStroke(l, strokeThickness)
	return l
end

-- Цепочка: [рюкзак] N ▶ [руда] M; две иконки одного размера и два числа:
-- N — руда в рюкзаке сейчас, M — всего сохранённой руды.
local function flowWidth(carryWidth: number, savedWidth: number): number
	return PITCH.Flow * 2 + ARROW_W + SPACE * 4 + carryWidth + savedWidth
end

local function rowWidths()
	return {
		Title = widthRatio("CHECKPOINT") * fontSize(PITCH.Title),
		Flow = flowWidth(widthRatio(NOMINAL_AMOUNT) * fontSize(AMOUNT_PITCH), widthRatio(NOMINAL_AMOUNT) * fontSize(AMOUNT_PITCH)),
		Hint = widthRatio("TOUCH TO SAVE ORE") * fontSize(PITCH.Hint),
	}
end

local function contentHeight(): number
	return PITCH.Title + PITCH.Flow + PITCH.Hint + GAP * 2
end

-- Подгоняет число под реальную ширину и сжимает цепочку, если число длиннее номинала.
local function setAmounts(info: Instance, carry: string, saved: string)
	local carryLabel = info:FindFirstChild("CarryValue", true) :: TextLabel?
	local savedLabel = info:FindFirstChild("SavedValue", true) :: TextLabel?
	local scale = info:FindFirstChild("FlowScale", true) :: UIScale?
	local width = info:GetAttribute("ContentWidth")
	if not (carryLabel and savedLabel and scale and width) then
		return
	end
	local font = fontSize(AMOUNT_PITCH)
	local carryW = widthRatio(carry) * font
	local savedW = widthRatio(saved) * font
	carryLabel.Text = carry
	savedLabel.Text = saved
	carryLabel.Size = UDim2.fromScale(carryW * 1.03 / width, font / PITCH.Flow)
	savedLabel.Size = UDim2.fromScale(savedW * 1.03 / width, font / PITCH.Flow)
	scale.Scale = math.min(1, width / flowWidth(carryW, savedW))
end

-- Один раз строит панель поверх SurfaceGui; всё в масштабе, поэтому одинаково на любой поверхности.
local function ensureInfo(gui: SurfaceGui): Frame
	local existing = gui:FindFirstChild(INFO_NAME)
	if existing then
		return existing :: Frame
	end

	local widths = rowWidths()
	local width = math.max(widths.Title, widths.Flow, widths.Hint)
	local height = contentHeight()

	local info = Instance.new("Frame")
	info.Name = INFO_NAME
	info.Size = UDim2.fromScale(1, 1)
	info.BackgroundTransparency = 1
	info:SetAttribute("ContentWidth", width)
	info.Parent = gui

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.97, 0.97)
	card.BackgroundTransparency = 1
	card.Parent = info
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = width / height
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = card

	local y = 0
	local function newRow(name: string, pitch: number): Frame
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0, y / height)
		row.Size = UDim2.fromScale(1, pitch / height)
		row.Parent = card
		y += pitch + GAP
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 0)
		list.Parent = row
		return row
	end

	local function textRow(name: string, pitch: number, text: string, props: { [string]: any }, stroke: number)
		local row = newRow(name, pitch)
		local font = fontSize(pitch)
		props.Text = text
		props.Size = UDim2.fromScale(widthRatio(text) * font * 1.03 / width, font / pitch)
		addText(row, props, stroke)
	end

	local function spacer(parent: Instance, order: number, w: number)
		local s = Instance.new("Frame")
		s.BackgroundTransparency = 1
		s.LayoutOrder = order
		s.Size = UDim2.fromScale(w / width, 0)
		s.Parent = parent
	end

	local function icon(parent: Instance, order: number, image: string, emoji: string)
		local obj: GuiObject
		if image ~= "" then
			local i = Instance.new("ImageLabel")
			i.Image = image
			i.ScaleType = Enum.ScaleType.Fit
			obj = i
		else
			local t = Instance.new("TextLabel")
			t.TextScaled = true
			t.Text = emoji
			obj = t
		end
		obj.BackgroundTransparency = 1
		obj.LayoutOrder = order
		obj.Size = UDim2.fromScale(PITCH.Flow / width, 1)
		obj.Parent = parent
	end

	local function arrow(parent: Instance, order: number)
		local font = fontSize(ARROW_W)
		addText(parent, {
			Name = "Arrow",
			LayoutOrder = order,
			Text = "▶",
			TextColor3 = ARROW_COLOR,
			Size = UDim2.fromScale(ARROW_W / width, font * 0.95 / PITCH.Flow),
		}, 3)
	end

	-- 1) CHECKPOINT — крупно, сверху
	textRow("TitleRow", PITCH.Title, "CHECKPOINT", { Name = "Title", TextColor3 = PASS_COLOR }, 3.5)

	-- 2) рюкзак ▶ руда N ▶ сохранение
	local flow = newRow("FlowRow", PITCH.Flow)
	local flowScale = Instance.new("UIScale")
	flowScale.Name = "FlowScale"
	flowScale.Parent = flow
	local font = fontSize(AMOUNT_PITCH)
	local function amount(order: number, name: string, color: Color3)
		addText(flow, {
			Name = name,
			LayoutOrder = order,
			Text = NOMINAL_AMOUNT,
			TextColor3 = color,
			Size = UDim2.fromScale(widthRatio(NOMINAL_AMOUNT) * font * 1.03 / width, font / PITCH.Flow),
		}, 3.5)
	end
	icon(flow, 1, BACKPACK_ICON, "🎒")
	spacer(flow, 2, SPACE)
	amount(3, "CarryValue", ORE_COLOR) -- руда в рюкзаке сейчас
	spacer(flow, 4, SPACE)
	arrow(flow, 5)
	spacer(flow, 6, SPACE)
	icon(flow, 7, ORE_ICON, "⛏")
	spacer(flow, 8, SPACE)
	amount(9, "SavedValue", PASS_COLOR) -- всего сохранено

	-- 3) действие — снизу
	textRow("HintRow", PITCH.Hint, "TOUCH TO SAVE ORE", { Name = "Hint" }, 2.5)

	return info
end

-- Всего сохранённой руды (profile.Ores), как в SavedOreMeter.
local function savedTotal(): number
	local total = 0
	for _, weight in pairs(Data.ores()) do
		total += tonumber(weight) or 0
	end
	return total
end

-- Включает SurfaceGui только у следующего чекпоинта и обновляет число сохраняемой руды.
local function refresh()
	if not folder then
		return
	end
	local guis = collectGuis()
	local target = nextIndex(guis)
	local carry = formatCount(Data.carryCount())
	local saved = formatCount(savedTotal())
	for gui, index in pairs(guis) do
		local active = index == target
		gui.Enabled = active
		if active then
			-- старые текстовые подписи больше не показываем
			for _, label in ipairs(gui:GetDescendants()) do
				if (label:IsA("TextLabel") or label:IsA("TextButton")) and not label:FindFirstAncestor(INFO_NAME) then
					label.Visible = false
				end
			end
			setAmounts(ensureInfo(gui), carry, saved)
		end
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
			if inst:IsA("SurfaceGui") or ((inst:IsA("TextLabel") or inst:IsA("TextButton")) and not inst:FindFirstAncestor(INFO_NAME)) then
				task.defer(refresh)
			end
		end)
		-- SurfaceGui могут жить и в PlayerGui с Adornee на чекпоинт
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		playerGui.DescendantAdded:Connect(function(inst)
			if inst:IsA("SurfaceGui") then
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
