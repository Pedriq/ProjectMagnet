local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local WorldState = require(ReplicatedStorage.ClientSource.UI.worldState)
local BaseStructures = require(ReplicatedStorage.ClientSource.UI.baseStructures)
local Guide = require(ReplicatedStorage.ClientSource.UI.tutorialGuide)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)

local source = vide.source

--[[
	tutorial — обучение новых игроков. Только клиент, только LocalPlayer.

	Не линейный сценарий, а СОСТОЯНИЕ: на каждом тике (TICK) для каждого шага считается
	«выполнен ли он фактически» по данным игрока (Data.*, WorldState, события пресса).
	Выполненный шаг запоминается (sticky), а выполненный более поздний шаг автоматически
	закрывает все предыдущие. Текущий шаг — первый невыполненный. Поэтому:
	  * сделал что-то раньше времени (набрал руду до 30 силы, купил магнит, продал
	    предметы…) — шаг молча пропускается, ничего не повторяется;
	  * ушёл, сменил зону, перезашёл — шаг выводится заново из сохранённых данных;
	  * игрок с уже пройденными шагами не видит ничего лишнего.

	Шаги (STAGES):
	  Magnetism  набрать 30 силы кликами
	  Ore        набить рюкзак рудой (путь к ближайшей руде)
	  Base       вернуться на базу (кнопка Base или своим ходом)
	  Unload     выгрузить руду в пресс (площадка Unloading)
	  Collect    забрать деньги (площадка Collect)
	  Save       накопить на первый магнит (мягкая цель, без стрелок)
	  Buy        купить первый доступный магнит (определяется динамически)
	  Free       пауза: подсказок нет, фоновое наблюдение
	  Capacity   купить прокачку Capacity (показывается сразу, как только хватает денег — с шага Save)
	  Finish     финальное сообщение -> Tutorial.Completed в профиле

	Наружу — Vide-источники для UI (оверлей, HUD, карточки панелей):
	  Tutorial.active / message / compact / tapHint / pulseBase / highlightMagnet / highlightStat
	  Tutorial.panel        — какое окно сейчас открыто (HUD пишет сюда openPanel)
	  Tutorial.notifyBaseClicked() — HUD сообщает о клике по кнопке Base

	Инициализация: Tutorial.start() из InitPlayerUI после Data.start() / WorldState.start().
]]
local Tutorial = {}

export type Message = { Title: string, Subtitle: string?, Progress: number? }

Tutorial.active = source(false)
Tutorial.message = source(nil :: Message?)
Tutorial.compact = source(false) -- мягкий шаг: сообщение сжимается в тонкую плашку
Tutorial.tapHint = source(false) -- пульс «кликай» на шаге Magnetism
Tutorial.pulseBase = source(false) -- подсветить кнопку Base в HUD
Tutorial.highlightMagnet = source(nil :: string?) -- ключ магнита, карточку которого подсветить
Tutorial.highlightStat = source(nil :: string?) -- ключ стата (Capacity), карточку которого подсветить
Tutorial.panel = source(nil :: string?) -- открытое окно HUD (пишет HUD)

-- Цель стоит в самом низу экрана (по центру); комбо и уведомления Feedback-слоя поднимаются на
-- PILL_RESERVE пикселей, пока она показана, и остаются над ней с прежним шагом между собой.
Tutorial.PILL_BOTTOM = 12
Tutorial.PILL_RESERVE = 80 -- заголовок 34 + подпись 20 + полоса 6 + шаги ≈ 66, плюс зазор до уведомлений

local STAGES = { "Magnetism", "Ore", "Base", "Unload", "Collect", "Save", "Buy", "Free", "Capacity", "Finish" }
local STAGE_INDEX = {}
for i, name in ipairs(STAGES) do
	STAGE_INDEX[name] = i
end
local LAST_TASK = STAGE_INDEX.Finish - 1 -- последний шаг с проверкой по данным (Capacity)

local TICK = 0.25
local MAGNETISM_GOAL = "30"
local CALM_SECONDS = 25 -- минимум «свободной игры» перед шагом Capacity
local COMPACT_AFTER = 6 -- через сколько секунд мягкий шаг сжимается
local FINISH_HOLD = 6 -- сколько держим финальное сообщение
local PROMPT_RESCAN = 3 -- как часто искать постройки, пока их нет
local FINAL_TEXT = "Collect Magnetism, mine rarer ores, and keep upgrading. Good luck!"

local player = Players.LocalPlayer

-- Самый лёгкий кусочек руды: меньше свободного места — рюкзак «полон» (как BAG FULL).
local MIN_PIECE_WEIGHT = math.huge
for _, oreId in ipairs(OreConfig.Order) do
	local ore = OreConfig.Get(oreId)
	if ore then
		MIN_PIECE_WEIGHT = math.min(MIN_PIECE_WEIGHT, ore.PieceWeight)
	end
end

---- State
local started = false
local finished = false
local done: { [number]: boolean } = {}
local latch = {
	bagFull = false, -- рюкзак был полон
	reachedBase = false, -- с полным рюкзаком оказался в SaveItemsZone
	baseClicked = false, -- нажал Base на шаге Base
	unloaded = false, -- OreUnloaded от пресса
	collected = false, -- деньги получены
	moneyAtUnload = nil :: any, -- Money в момент выгрузки (рост после неё = деньги пришли)
	savedUp = false, -- хватало на первый магнит
	calmOver = false, -- пауза между магнитом и Capacity прошла
}
local currentStage: string? = nil
local stageSince = 0
local freeSince: number? = nil

local promptCache: { [string]: { { Prompt: ProximityPrompt, Building: Instance } } } = {}
local promptScanned: { [string]: number } = {}

--== помощники по данным ====================================================
local function safeMeeq(a: any, b: any): boolean
	local ok, result = pcall(EtNum.meeq, a, b)
	return ok and result == true
end

local function safeMoreThan(a: any, b: any): boolean
	local ok, result = pcall(EtNum.me, a, b)
	return ok and result == true
end

local function toNumber(value: any): number
	local ok, n = pcall(function()
		return EtNum.toNumber(EtNum.convert(value))
	end)
	return if ok and n == n then n else 0
end

local function isBagFull(): boolean
	return Data.carryCount() > 0 and Data.carryCapacity() - Data.carryCount() < MIN_PIECE_WEIGHT
end

local function hasKeys(map: any): boolean
	return type(map) == "table" and next(map) ~= nil
end

-- Первый магнит из магазина (по порядку), который игрок может купить за Money и ещё не имеет.
local function firstAvailableMagnet(): string?
	local owned = Data.ownedMagnets()
	for _, key in ipairs(MagnetData.Order) do
		local magnet = MagnetData[key]
		if magnet and magnet.Price and not owned[key] then
			return key
		end
	end
	return nil
end

local function ownsPurchasedMagnet(): boolean
	local owned = Data.ownedMagnets()
	for _, key in ipairs(MagnetData.Order) do
		local magnet = MagnetData[key]
		if magnet and magnet.Price and owned[key] then
			return true
		end
	end
	return false
end

local function capacityLevel(): number
	return Data.upgradeLevels().Capacity or 1
end

local function capacityCost(): string
	return StatUpgradesConfig.CostFor("Capacity", capacityLevel())
end

local function magnetismReached(): boolean
	return safeMeeq(Data.magnetism(), MAGNETISM_GOAL)
end

--== поиск целей в мире =====================================================
local function characterRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function positionOf(instance: Instance?): Vector3?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	return nil
end

-- Ближайшая руда игрока (предпочитаем самую первую по тирам). -> позиция, модель для подсветки.
local function nearestOre(): (Vector3?, Instance?)
	local root = characterRoot()
	local rocksRoot = Workspace:FindFirstChild("PlayersRock")
	local folder = rocksRoot and rocksRoot:FindFirstChild(`{player.UserId}_Rock`)
	if not root or not folder then
		return nil, nil
	end

	local firstOre = OreConfig.Order[1]
	local best: BasePart? = nil
	local bestPreferred = false
	local bestDistance = math.huge

	-- хитбоксы лежат глубже: PlayersRock/<id>_Rock/<stripId>/Rock_<n>
	for _, rock in ipairs(folder:GetDescendants()) do
		if rock:IsA("BasePart") then
			local preferred = rock:GetAttribute("Section") == firstOre
			local distance = (rock.Position - root.Position).Magnitude
			if (preferred and not bestPreferred) or (preferred == bestPreferred and distance < bestDistance) then
				best, bestPreferred, bestDistance = rock, preferred, distance
			end
		end
	end

	if not best then
		return nil, nil
	end

	local model: Instance? = nil
	local ok, rockController = pcall(Knit.GetController, "RockController")
	if ok and rockController and rockController.VisualizedRocks then
		local visual = rockController.VisualizedRocks[`{best:GetAttribute("StripId")}_{best:GetAttribute("RockIndex")}`]
		model = visual and visual.Model
	end
	return best.Position, model or best
end

-- Площадка пресса (Unloading / Collect). -> позиция, что подсвечивать.
local function pressPad(names: { string }): (Vector3?, Instance?)
	local press = Workspace:FindFirstChild(PressConfig.PRESS_NAME)
	if not press then
		return nil, nil
	end
	for _, name in ipairs(names) do
		local pad = press:FindFirstChild(name)
		if pad then
			local floor = pad:FindFirstChild("ZoneFloor") or pad
			return positionOf(floor), pad
		end
	end
	return nil, nil
end

-- Все постройки базы с окном `panelKey` (во всех мирах): ProximityPrompt'ы у NPC.
local function scanBuildings(panelKey: string)
	local list = {}
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("ProximityPrompt") and BaseStructures.panelKeyFromPrompt(instance) == panelKey then
			-- поднимаемся к самой верхней постройке с тем же именем (NPC внутри постройки «Buy» — тоже «Buy»)
			local building: Instance = instance.Parent :: Instance
			local node: Instance? = instance.Parent
			while node and node ~= Workspace do
				if BaseStructures.PANEL_BY_BUILDING[node.Name] == panelKey then
					building = node
				end
				node = node.Parent
			end
			table.insert(list, { Prompt = instance, Building = building })
		end
	end
	promptCache[panelKey] = list
	promptScanned[panelKey] = os.clock()
end

-- Ближайшая к игроку постройка окна `panelKey`. -> позиция, постройка для подсветки.
local function nearestBuilding(panelKey: string): (Vector3?, Instance?)
	local root = characterRoot()
	if not root then
		return nil, nil
	end

	local list = promptCache[panelKey]
	local stale = false
	if list then
		for _, entry in ipairs(list) do
			if not entry.Prompt:IsDescendantOf(Workspace) then
				stale = true
				break
			end
		end
	end
	if not list or stale or (#list == 0 and os.clock() - (promptScanned[panelKey] or 0) > PROMPT_RESCAN) then
		scanBuildings(panelKey)
		list = promptCache[panelKey]
	end

	local bestPosition: Vector3? = nil
	local bestBuilding: Instance? = nil
	local bestDistance = math.huge
	for _, entry in ipairs(list) do
		local position = positionOf(entry.Prompt.Parent)
		if position then
			local distance = (position - root.Position).Magnitude
			if distance < bestDistance then
				bestPosition, bestBuilding, bestDistance = position, entry.Building, distance
			end
		end
	end
	return bestPosition, bestBuilding
end

--== запись состояния для UI (только при изменении, чтобы не дёргать подписчиков) ==
local function setMessage(title: string?, subtitle: string?, progress: number?)
	if not title then
		if Tutorial.message() ~= nil then
			Tutorial.message(nil)
		end
		return
	end
	if progress then
		progress = math.floor(math.clamp(progress, 0, 1) * 100) / 100
	end
	local current = Tutorial.message()
	if current and current.Title == title and current.Subtitle == subtitle and current.Progress == progress then
		return
	end
	Tutorial.message({ Title = title, Subtitle = subtitle, Progress = progress })
end

local function setSource(src: (any?) -> any, value: any)
	if src() ~= value then
		src(value)
	end
end

--== вычисление «что уже сделано» ============================================
local function updateLatches()
	if isBagFull() then
		latch.bagFull = true
	end
	if latch.bagFull and WorldState.inSaveZone() then
		latch.reachedBase = true
	end

	local pressing = hasKeys(Data.pressOres()) or hasKeys(Data.items())
	if (latch.unloaded or pressing) and latch.moneyAtUnload == nil then
		latch.moneyAtUnload = Data.money()
	end
	if pressing then
		latch.unloaded = true
	end
	if latch.unloaded and latch.moneyAtUnload ~= nil and safeMoreThan(Data.money(), latch.moneyAtUnload) then
		latch.collected = true
	end

	local key = firstAvailableMagnet()
	local magnet = key and MagnetData[key]
	if not magnet or safeMeeq(Data.money(), magnet.Price) then
		latch.savedUp = true
	end
end

local function updateDone()
	local savedOre = hasKeys(Data.ores())
	local pressing = hasKeys(Data.pressOres()) or hasKeys(Data.items())
	local capacityBought = capacityLevel() > 1

	local raw = {
		[1] = magnetismReached(),
		[2] = latch.bagFull or savedOre or pressing,
		[3] = latch.reachedBase or latch.baseClicked or savedOre or pressing,
		[4] = latch.unloaded or pressing,
		[5] = latch.collected,
		[6] = latch.savedUp,
		[7] = ownsPurchasedMagnet(),
		[8] = latch.calmOver or capacityBought,
		[9] = capacityBought,
	}
	for i = 1, LAST_TASK do
		if raw[i] then
			done[i] = true
		end
	end
	-- выполненный поздний шаг закрывает все ранние. Free/Capacity закрывают только основной цикл
	-- (до Collect): ранняя покупка Capacity не должна отменять шаги Save/Buy (первый магнит).
	for i = STAGE_INDEX.Buy, 2, -1 do
		if done[i] then
			done[i - 1] = true
		end
	end
	if done[STAGE_INDEX.Free] or done[STAGE_INDEX.Capacity] then
		for i = 1, STAGE_INDEX.Collect do
			done[i] = true
		end
	end
	if done[STAGE_INDEX.Capacity] and done[STAGE_INDEX.Buy] then
		done[STAGE_INDEX.Free] = true
	end
end

-- Capacity можно купить раньше срока (хватает денег на шаге Save/Buy/Free): подсказываем сразу,
-- не дожидаясь паузы и покупки магнита. Пока открыт магазин магнитов на шаге Buy — не перебиваем.
local function capacityAvailableNow(stage: string): boolean
	local index = STAGE_INDEX[stage]
	if index < STAGE_INDEX.Save or index > STAGE_INDEX.Free or done[STAGE_INDEX.Capacity] then
		return false
	end
	if stage == "Buy" and Tutorial.panel() == "magnets" then
		return false
	end
	return capacityLevel() <= 1 and safeMeeq(Data.money(), capacityCost())
end

local function firstPendingStage(): string
	for i = 1, LAST_TASK do
		if not done[i] then
			return STAGES[i]
		end
	end
	return "Finish"
end

--== подсказки по шагам ======================================================
-- Описание шага: пишет сообщение/подсветки и возвращает (позиция, что подсвечивать) для мировой стрелки.
local function describe(stage: string): (Vector3?, Instance?)
	local panel = Tutorial.panel()
	local highlightMagnet: string? = nil
	local highlightStat: string? = nil
	local pulseBase = false
	local tapHint = false
	local compact = false
	local targetPosition: Vector3? = nil
	local targetAdornee: Instance? = nil

	if stage == "Magnetism" then
		tapHint = true
		local current = toNumber(Data.magnetism())
		local goal = tonumber(MAGNETISM_GOAL) :: number
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		setMessage(
			if touchOnly then "TAP TO COLLECT MAGNETISM" else "CLICK TO COLLECT MAGNETISM",
			`{math.floor(math.min(current, goal))} / {MAGNETISM_GOAL}`,
			current / goal
		)
	elseif stage == "Ore" then
		setMessage("MINE SOME ORE", "Fill your bag — follow the arrow", Data.carryCount() / math.max(Data.carryCapacity(), 1))
		targetPosition, targetAdornee = nearestOre()
	elseif stage == "Base" then
		local baseButtonVisible = not WorldState.showXpBar()
		pulseBase = baseButtonVisible
		if baseButtonVisible then
			setMessage("BAG FULL!", "Press BASE to return and unload your ore")
		else
			setMessage("BAG FULL!", "Head back to base to unload your ore")
			targetPosition, targetAdornee = pressPad(PressConfig.UNLOADING_NAMES)
		end
	elseif stage == "Unload" then
		setMessage("UNLOAD YOUR ORE", "Step on the glowing pad")
		targetPosition, targetAdornee = pressPad(PressConfig.UNLOADING_NAMES)
	elseif stage == "Collect" then
		if Data.autoCollectPass() then
			setMessage("PRESSING YOUR ORE", "Your money arrives automatically")
		else
			setMessage("COLLECT YOUR MONEY", "Stand on the Collect pad when the press is done")
			targetPosition, targetAdornee = pressPad(PressConfig.COLLECT_NAMES)
		end
	elseif stage == "Save" then
		local key = firstAvailableMagnet()
		local magnet = key and MagnetData[key]
		if magnet then
			local price = magnet.Price
			local progress = if safeMeeq(Data.money(), price)
				then 1
				else toNumber(Data.money()) / math.max(toNumber(price), 1)
			setMessage(
				"SAVE UP FOR YOUR FIRST MAGNET",
				`${Format.short(Data.money())} / ${Format.short(price)}`,
				progress
			)
		end
		compact = os.clock() - stageSince > COMPACT_AFTER
	elseif stage == "Buy" then
		local key = firstAvailableMagnet()
		local magnet = key and MagnetData[key]
		if key and magnet then
			local name = magnet.Display or magnet.Name
			if not safeMeeq(Data.money(), magnet.Price) then
				-- потратил деньги по дороге: цель мягкая, без стрелок
				setMessage("EARN MORE FOR " .. string.upper(name), `Need ${Format.short(magnet.Price)}`)
				compact = true
			elseif panel == "magnets" then
				highlightMagnet = key
				setMessage("BUY " .. string.upper(name), "Tap BUY on the highlighted magnet")
			else
				setMessage("BUY YOUR FIRST MAGNET", `Visit the Magnet Shop — {name}`)
				targetPosition, targetAdornee = nearestBuilding("magnets")
			end
		end
	elseif stage == "Capacity" then
		local cost = capacityCost()
		if not safeMeeq(Data.money(), cost) then
			setMessage("EARN MORE FOR CAPACITY", `Need ${Format.short(cost)}`)
			compact = true
		elseif panel == "upgrades" then
			highlightStat = "Capacity"
			setMessage("UPGRADE CAPACITY", "Carry more ore before returning to base")
		else
			setMessage("UPGRADE CAPACITY", "Carry more ore before returning to base")
			targetPosition, targetAdornee = nearestBuilding("upgrades")
		end
	elseif stage == "Finish" then
		setMessage("TUTORIAL COMPLETE", FINAL_TEXT)
	else -- Free: подсказок нет
		setMessage(nil)
	end

	setSource(Tutorial.highlightMagnet, highlightMagnet)
	setSource(Tutorial.highlightStat, highlightStat)
	setSource(Tutorial.pulseBase, pulseBase)
	setSource(Tutorial.tapHint, tapHint)
	setSource(Tutorial.compact, compact)

	-- пока открыто любое окно, мировую стрелку не показываем
	if panel ~= nil then
		return nil, nil
	end
	return targetPosition, targetAdornee
end

local function finish(silent: boolean)
	if finished then
		return
	end
	finished = true
	Guide.destroy()
	setMessage(nil)
	setSource(Tutorial.highlightMagnet, nil)
	setSource(Tutorial.highlightStat, nil)
	setSource(Tutorial.pulseBase, false)
	setSource(Tutorial.tapHint, false)
	setSource(Tutorial.compact, false)
	Tutorial.active(false)
	if not silent then
		sfx.play("GoalReady")
	end
	Knit.GetService("PlayerManagerService"):CompleteTutorial():catch(warn)
end

local function tick(firstTick: boolean)
	updateLatches()
	updateDone()

	local stage = firstPendingStage()
	if capacityAvailableNow(stage) then
		stage = "Capacity"
	end

	-- Игрок уже прошёл всё до старта обучения (опытный/старый профиль): тихо закрываем
	if firstTick and stage == "Finish" then
		finish(true)
		return
	end

	if stage ~= currentStage then
		if currentStage ~= nil then
			sfx.play("GoalReady", { volume = 0.6 })
		end
		currentStage = stage
		stageSince = os.clock()
		if stage == "Free" then
			freeSince = os.clock()
		end
	end

	-- пауза перед Capacity: прошло время, хватает денег, окно не открыто
	if stage == "Free" and not latch.calmOver then
		local since = freeSince or os.clock()
		if
			os.clock() - since >= CALM_SECONDS
			and Tutorial.panel() == nil
			and safeMeeq(Data.money(), capacityCost())
		then
			latch.calmOver = true
		end
	end

	local position, adornee = describe(stage)
	Guide.set(position, adornee)

	if stage == "Finish" and os.clock() - stageSince >= FINISH_HOLD then
		finish(false)
	end
end

-- HUD: игрок нажал кнопку Base. Засчитываем только на шаге Base (раньше руды у него нет).
function Tutorial.notifyBaseClicked()
	if currentStage == "Base" then
		latch.baseClicked = true
	end
end

function Tutorial.start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		-- ждём профиль (там и флаг Completed); уже пройденное обучение не запускаем
		while not Data.ready() do
			task.wait(0.2)
		end
		if Data.tutorialCompleted() then
			return
		end

		local PressService = Knit.GetService("PressService")
		PressService.OreUnloaded:Connect(function()
			latch.unloaded = true
			if latch.moneyAtUnload == nil then
				latch.moneyAtUnload = Data.money()
			end
		end)
		PressService.MoneyCollected:Connect(function()
			latch.unloaded = true
			latch.collected = true
		end)

		Tutorial.active(true)
		local first = true
		while not finished do
			local ok, err = pcall(tick, first)
			if not ok then
				warn("[Tutorial] tick failed:", err)
			end
			first = false
			task.wait(TICK)
		end
	end)
end

return Tutorial
