local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local WorldState = require(ReplicatedStorage.ClientSource.UI.worldState)
local viewportScale = require(ReplicatedStorage.ClientSource.UI.viewportScale)
local combo = require(ReplicatedStorage.ClientSource.combo)
local juice = require(ReplicatedStorage.ClientSource.juice)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local RebirthEffect = require(ReplicatedStorage.ClientSource.UI.components.RebirthEffect)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)

local create = vide.create
local effect = vide.effect
local cleanup = vide.cleanup
local untrack = vide.untrack

--[[
	FeedbackOverlay — слой обратной связи поверх HUD (отдельный ScreenGui, см. App):

	  * Баннеры (очередь, по одному): LEVEL UP, REBIRTH READY, рубежи комбо,
	    сбор денег с пресса.
	  * Счётчик комбо ручного клика с убывающей полоской-таймером.
	  * BAG FULL: пульсирующее предупреждение, пока инвентарь переноски полон. Если место ещё
	    есть, но руда слишком тяжёлая (сервер шлёт CarryBlocked) — «ORE TOO HEAVY!» с весом руды и
	    доступным местом. Состояние всегда берётся из текущего инвентаря: после сброса на
	    чекпоинте предупреждение пропадает сразу. Рядом — кнопка Level Up Capacity (Game Pass-скип).
	  * Контекстные подсказки действий внизу по центру («You can buy a new
	    magnet» — когда денег хватает на самый дорогой доступный магнит; «Not enough
	    rebirths» у закрытой зоны) — одно уведомление, новое заменяет текущее (pushNotice).
	  * «+$X» при каждом приросте денег.
	  * Вспышка экрана на LEVEL UP и Legendary+.
]]

-- язык цвета UI.theme: прогресс/сила — электрический, деньги — зелёный, опасность — красный
local GOLD = Theme.ElectricBright -- LEVEL UP, комбо, сила
local GREEN = Theme.Money
local RED = Theme.Danger
local WHITE = Color3.new(1, 1, 1)

local BANNER_HOLD = 1.3
local BANNER_MAX_QUEUE = 3

-- Самый лёгкий кусочек руды: если свободного места меньше — сервер больше не
-- бьёт ни один камень (PlayerMagnetHitboxManager:ApplyHit -> CanCarryOrePiece).
local MIN_PIECE_WEIGHT = math.huge
for _, oreId in ipairs(OreConfig.Order) do
	local ore = OreConfig.Get(oreId)
	if ore then
		MIN_PIECE_WEIGHT = math.min(MIN_PIECE_WEIGHT, ore.PieceWeight)
	end
end

local function isBagFull(): boolean
	return Data.carryCapacity() - Data.carryCount() < MIN_PIECE_WEIGHT
end

-- Самый дорогой из доступных сейчас магнитов: последний по порядку магазина, которым
-- игрок ещё не владеет и который продаётся за Money. Подсказка «можно купить новый
-- магнит» показывается, только когда денег хватает именно на него — а не по разу на
-- каждый следующий магнит после каждой покупки.
local function topMagnetKey(): string?
	local owned = Data.ownedMagnets()
	local order = MagnetData.Order
	for i = #order, 1, -1 do
		local key = order[i]
		local magnet = MagnetData[key]
		if magnet and magnet.Price and not owned[key] then
			return key
		end
	end
	return nil
end

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2.5
	s.Color = color or Color3.new(0, 0, 0)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = WHITE
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	stroke(l, props.TextSize and math.max(props.TextSize / 12, 2) or 2.5)
	return l
end

local function FeedbackOverlay()
	local player = Players.LocalPlayer
	local PressService = Knit.GetService("PressService")
	local AutoClickZoneService = Knit.GetService("AutoClickZoneService")
	local PlayerManagerService = Knit.GetService("PlayerManagerService")

	local guiScale = viewportScale()

	local root = create("Frame")({
		Name = "Feedback",
		BackgroundTransparency = 1,
		Size = function()
			local s = guiScale()
			return UDim2.fromScale(1 / s, 1 / s)
		end,
		create("UIScale")({ Scale = guiScale }),
	}) :: Frame

	local connections: { RBXScriptConnection | any } = {}
	cleanup(function()
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
	end)

	--=== вспышка экрана ======================================================
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = root

	local function flashScreen(color: Color3, strength: number?)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 1 - (strength or 0.45)
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end

	local playRebirthEffect = RebirthEffect(root)

	--=== баннеры =============================================================
	local bannerHolder = Instance.new("Frame")
	bannerHolder.Name = "Banners"
	bannerHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerHolder.Position = UDim2.fromScale(0.5, 0.24)
	bannerHolder.Size = UDim2.fromOffset(640, 120)
	bannerHolder.BackgroundTransparency = 1
	bannerHolder.ZIndex = 5
	bannerHolder.Parent = root

	type Banner = { title: string, subtitle: string?, color: Color3, priority: number }
	local queue: { Banner } = {}
	local showing = false

	local function showNext()
		local banner = table.remove(queue, 1)
		if not banner then
			showing = false
			return
		end
		showing = true

		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = bannerHolder

		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = frame

		local title = label({
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(1, 0, 0, 64),
			TextSize = 58,
			Text = banner.title,
			TextColor3 = banner.color,
		})
		title.Parent = frame

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(WHITE:Lerp(banner.color, 0.4), banner.color)
		gradient.Rotation = 90
		gradient.Parent = title

		local subtitle
		if banner.subtitle then
			subtitle = label({
				Name = "Subtitle",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 66),
				Size = UDim2.new(1, 0, 0, 34),
				TextSize = 28,
				Text = banner.subtitle,
			})
			subtitle.Parent = frame
		end

		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		-- лёгкое «покачивание» заголовка
		title.Rotation = -6
		TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Rotation = 0,
		}):Play()

		task.delay(BANNER_HOLD, function()
			local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(scale, out, { Scale = 1.15 }):Play()
			for _, l in ipairs({ title, subtitle }) do
				if l then
					TweenService:Create(l, out, { TextTransparency = 1 }):Play()
					local s = l:FindFirstChildOfClass("UIStroke")
					if s then
						TweenService:Create(s, out, { Transparency = 1 }):Play()
					end
				end
			end
			task.delay(0.27, function()
				frame:Destroy()
				showNext()
			end)
		end)
	end

	-- priority: чем больше, тем важнее; при переполнении очереди выкидываем
	-- наименее важные (поток Epic-предметов из пресса не должен душить LEVEL UP).
	local function pushBanner(banner: Banner)
		table.insert(queue, banner)
		table.sort(queue, function(a, b)
			return a.priority > b.priority
		end)
		while #queue > BANNER_MAX_QUEUE do
			table.remove(queue)
		end
		if not showing then
			showNext()
		end
	end

	--=== контекстные подсказки действий (внизу по центру) ===================
	-- «You can buy a new magnet», «Not enough rebirths» и т.п.: не перебивают центральные
	-- баннеры, а тихо выезжают снизу. Показывается ОДНО уведомление: любое новое
	-- сразу заменяет текущее и заново отсчитывает своё время показа (без очереди — иначе
	-- при быстрой смене зон «Not enough rebirths» зависало и новое не появлялось).
	local NOTICE_HOLD = 2.5 -- по умолчанию, секунд; у уведомления можно задать своё (hold)
	local ZONE_NOTICE_HOLD = 1.6 -- «Not enough rebirths» и т.п.: коротко, чтобы не висело

	local noticeHolder = Instance.new("Frame")
	noticeHolder.Name = "ActionNotices"
	noticeHolder.AnchorPoint = Vector2.new(0.5, 1)
	noticeHolder.Position = UDim2.new(0.5, 0, 1, -16)
	noticeHolder.Size = UDim2.fromOffset(520, 64)
	noticeHolder.BackgroundTransparency = 1
	noticeHolder.ClipsDescendants = true
	noticeHolder.ZIndex = 5
	noticeHolder.Parent = root

	type Notice = { key: string, title: string, subtitle: string?, color: Color3, hold: number? }
	local currentNotice: Notice? = nil
	local currentPill: Frame? = nil
	local noticeToken = 0 -- меняется на каждое новое уведомление; старые таймеры сверяют его и молчат

	local function showNotice(notice: Notice)
		-- то же уведомление (тот же ключ и текст) уже на экране — просто продлеваем показ,
		-- без повторной анимации выезда
		local sameAsCurrent = currentPill ~= nil
			and currentNotice ~= nil
			and currentNotice.key == notice.key
			and currentNotice.title == notice.title
			and currentNotice.subtitle == notice.subtitle

		noticeToken += 1
		local token = noticeToken
		currentNotice = notice

		if sameAsCurrent then
			task.delay(notice.hold or NOTICE_HOLD, function()
				if token ~= noticeToken then
					return
				end
				local pill = currentPill
				currentPill = nil
				currentNotice = nil
				if not pill then
					return
				end
				local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TweenService:Create(pill, out, { Position = UDim2.new(0.5, 0, 1, 70) }):Play()
				task.delay(0.27, function()
					pill:Destroy()
				end)
			end)
			return
		end

		-- другое уведомление: прежнее убираем сразу
		if currentPill then
			currentPill:Destroy()
			currentPill = nil
		end

		local pill = Instance.new("Frame")
		pill.Name = "Notice"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, 70) -- старт под краем, выезжает вверх
		pill.Size = UDim2.new(1, 0, 0, 56)
		pill.BackgroundColor3 = Theme.Steel800
		pill.BackgroundTransparency = Theme.PanelBodyTransparency
		pill.BorderSizePixel = 0
		pill.Parent = noticeHolder
		currentPill = pill

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = pill
		local pillStroke = stroke(pill, 2.5, notice.color)
		pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Position = UDim2.fromOffset(10, 10)
		accent.Size = UDim2.new(0, 6, 1, -20)
		accent.BackgroundColor3 = notice.color
		accent.BorderSizePixel = 0
		accent.Parent = pill
		local accentCorner = Instance.new("UICorner")
		accentCorner.CornerRadius = UDim.new(1, 0)
		accentCorner.Parent = accent

		local title = label({
			Name = "Title",
			Position = UDim2.fromOffset(28, notice.subtitle and 6 or 0),
			Size = notice.subtitle and UDim2.new(1, -40, 0, 26) or UDim2.new(1, -40, 1, 0),
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = notice.color:Lerp(WHITE, 0.35),
			Text = notice.title,
		})
		title.Parent = pill

		local subtitle
		if notice.subtitle then
			subtitle = label({
				Name = "Subtitle",
				Position = UDim2.fromOffset(28, 32),
				Size = UDim2.new(1, -40, 0, 18),
				TextSize = 16,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.Text,
				Text = notice.subtitle,
			})
			subtitle.Parent = pill
		end

		TweenService:Create(pill, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 1, -4),
		}):Play()

		task.delay(notice.hold or NOTICE_HOLD, function()
			if token ~= noticeToken then
				return -- уже заменено другим уведомлением (его pill старый показ уже убрал)
			end
			currentPill = nil
			currentNotice = nil
			local out = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(pill, out, { Position = UDim2.new(0.5, 0, 1, 70) }):Play()
			task.delay(0.27, function()
				pill:Destroy()
			end)
		end)
	end

	local function pushNotice(notice: Notice)
		showNotice(notice)
	end

	--=== «+$X» у денег =======================================================
	local moneyToasts = Instance.new("Frame")
	moneyToasts.Name = "MoneyToasts"
	moneyToasts.AnchorPoint = Vector2.new(0, 1)
	moneyToasts.Position = UDim2.new(0, 240, 1, -20)
	moneyToasts.Size = UDim2.fromOffset(260, 40)
	moneyToasts.BackgroundTransparency = 1
	moneyToasts.Parent = root

	local function moneyToast(amount: any)
		local l = label({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 1),
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = GREEN,
			Text = "+$" .. Format.short(amount),
		})
		l.Parent = moneyToasts
		local s = Instance.new("UIScale")
		s.Scale = 1.5
		s.Parent = l
		TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 1, -70),
		}):Play()
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7)
		TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(l:FindFirstChildOfClass("UIStroke") :: UIStroke, fade, { Transparency = 1 }):Play()
		task.delay(1.15, function()
			l:Destroy()
		end)
	end

	--=== счётчик комбо =======================================================
	local comboFrame = create("Frame")({
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(220, 70),
		BackgroundTransparency = 1,
		Visible = function()
			return combo.count() >= 3
		end,

		create("TextLabel")({
			Name = "Count",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 44),
			Font = Enum.Font.GothamBlack,
			TextSize = 42,
			TextColor3 = function()
				return GOLD:Lerp(Theme.CopperBright, math.clamp(combo.count() / 60, 0, 1))
			end,
			Text = function()
				return "x" .. combo.count() .. " COMBO"
			end,
			create("UIStroke")({ Thickness = 3 }),
		}),
		create("TextLabel")({
			Name = "Bonus",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 0, 18),
			Font = Enum.Font.GothamBlack,
			TextSize = 17,
			TextColor3 = WHITE,
			Text = function()
				return "+" .. math.floor((combo.multiplier() - 1) * 100 + 0.5) .. "% POWER"
			end,
			create("UIStroke")({ Thickness = 2 }),
		}),
		create("Frame")({
			Name = "Timer",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 63),
			Size = UDim2.fromOffset(160, 6),
			BackgroundColor3 = Theme.Steel900,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("Frame")({
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = GOLD,
				Size = function()
					return UDim2.fromScale(combo.timeLeft(), 1)
				end,
				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			}),
		}),
	}) :: Frame
	comboFrame.Parent = root

	local comboScale = Instance.new("UIScale")
	comboScale.Parent = comboFrame
	table.insert(
		connections,
		combo.Clicked:Connect(function()
			comboScale.Scale = 1.18
			TweenService:Create(comboScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		end)
	)
	table.insert(
		connections,
		combo.Milestone:Connect(function(count)
			pushBanner({
				title = count .. " COMBO!",
				subtitle = "+" .. math.floor((combo.multiplier() - 1) * 100 + 0.5) .. "% power per click",
				color = Theme.CopperBright,
				priority = 1,
			})
		end)
	)

	--=== BAG FULL ============================================================
	local bagAlert = Instance.new("Frame")
	bagAlert.Name = "BagFull"
	bagAlert.AnchorPoint = Vector2.new(0.5, 0.5)
	bagAlert.Position = UDim2.fromScale(0.5, 0.36)
	bagAlert.Size = UDim2.fromOffset(520, 150)
	bagAlert.BackgroundTransparency = 1
	bagAlert.Visible = false
	bagAlert.Parent = root

	local bagTitle = label({
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = 48,
		TextColor3 = RED,
		Text = "BAG FULL!",
	})
	bagTitle.Parent = bagAlert
	local bagHint = label({
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = 24,
		Text = "Return to base to save your ore",
	})
	bagHint.Parent = bagAlert
	local bagScale = Instance.new("UIScale")
	bagScale.Parent = bagAlert

	-- Кнопка «купить Capacity» (дев-продукт ступени, как в панели Upgrades): видна вместе с
	-- предупреждением, т.е. ровно когда игроку не хватает места.
	local buyCapacity = Instance.new("TextButton")
	buyCapacity.Name = "BuyCapacity"
	buyCapacity.AnchorPoint = Vector2.new(0.5, 0)
	buyCapacity.Position = UDim2.new(0.5, 0, 0, 90)
	buyCapacity.Size = UDim2.fromOffset(330, 48)
	buyCapacity.AutoButtonColor = false
	buyCapacity.BackgroundColor3 = WHITE
	buyCapacity.Font = Enum.Font.GothamBlack
	buyCapacity.TextSize = 22
	buyCapacity.TextColor3 = WHITE
	buyCapacity.Text = ""
	buyCapacity.Parent = bagAlert
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = buyCapacity
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Theme.ButtonGold:Lerp(WHITE, 0.3), Theme.ButtonGold)
		g.Parent = buyCapacity
		local st = Instance.new("UIStroke")
		st.Thickness = 2.5
		st.Color = Color3.new(0, 0, 0)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = buyCapacity
		local ts = Instance.new("UIStroke")
		ts.Thickness = 2
		ts.Color = Color3.new(0, 0, 0)
		ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		ts.Parent = buyCapacity
	end

	local function refreshBuyCapacityText()
		local level = Data.upgradeLevels()["Capacity"] or 1
		local step = StatUpgradesConfig.RobuxStepFor("Capacity", level)
		local price = step and step.Price > 0 and tostring(step.Price) or "?"
		buyCapacity.Text = `Level Up Capacity  \u{E002}{price}`
	end
	refreshBuyCapacityText()

	local capacityHovered = false
	buyCapacity.MouseEnter:Connect(function()
		capacityHovered = true
	end)
	buyCapacity.MouseLeave:Connect(function()
		capacityHovered = false
	end)
	buyCapacity.Activated:Connect(function()
		sfx.play("ClickUI")
		PlayerManagerService:PromptStatRobuxUpgrade("Capacity"):catch(warn)
	end)

	-- Состояние предупреждения ВСЕГДА выводится из текущего инвентаря (Data.carryCount /
	-- Data.carryCapacity), а не из «последнего события»: сохранили руду на чекпоинте / выбросили
	-- в пресс — свободного места снова хватает, и предупреждение пропадает в тот же кадр.
	--   * BAG FULL      — свободного места меньше самого лёгкого кусочка руды (isBagFull);
	--   * ORE TOO HEAVY — место ещё есть, но меньше веса кусочка руды, которую игрок пытается
	--                     собрать (его присылает сервер сигналом CarryBlocked): показываем вес
	--                     руды и сколько места доступно.
	local BLOCKED_HOLD = 4 -- сколько держим «too heavy» после последней попытки (и пока курсор над кнопкой)
	local blockedUntil = 0
	local blockedNeed = 0 -- вес кусочка, который не влез
	table.insert(
		connections,
		PlayerManagerService.CarryBlocked:Connect(function(needed)
			if WorldState.inSaveZone() then
				return
			end
			blockedNeed = needed or 0
			blockedUntil = os.clock() + BLOCKED_HOLD
			refreshBuyCapacityText()
		end)
	)

	local function freeSpace(): number
		return math.max(Data.carryCapacity() - Data.carryCount(), 0)
	end

	-- nil — предупреждение не нужно; иначе "full" | "heavy"
	local function bagMode(): string?
		if not Data.ready() or WorldState.inSaveZone() then
			return nil
		end
		if isBagFull() then
			return "full"
		end
		if blockedNeed > 0 and os.clock() < blockedUntil then
			if freeSpace() < blockedNeed then
				return "heavy"
			end
			-- места снова хватает (чекпоинт/сохранение) — забываем попытку
			blockedNeed = 0
			blockedUntil = 0
		end
		return nil
	end

	local WARNING = Theme.Warning
	local bagPulse = 0
	local shownMode: string? = nil
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			if capacityHovered and shownMode ~= nil then
				blockedUntil = math.max(blockedUntil, os.clock() + 1)
			end

			local mode = bagMode()
			if mode ~= shownMode then
				local previous = shownMode
				shownMode = mode
				bagAlert.Visible = mode ~= nil
				if mode then
					refreshBuyCapacityText()
					if previous == nil then
						sfx.play("BagFull")
						juice.shake(0.3)
						flashScreen(if mode == "full" then RED else WARNING, 0.25)
					end
				end
			end

			if mode == "full" then
				bagTitle.Text = "BAG FULL!"
				bagTitle.TextColor3 = RED
				bagHint.Text = "Return to base to save your ore"
			elseif mode == "heavy" then
				bagTitle.Text = "ORE TOO HEAVY!"
				bagTitle.TextColor3 = WARNING
				bagHint.Text = `Ore Weight: {blockedNeed} | Available: {math.floor(freeSpace())}`
			end

			if mode then
				bagPulse += dt * 5
				bagScale.Scale = 1 + math.abs(math.sin(bagPulse)) * 0.08
			end
		end)
	)

	--=== реакции на данные ===================================================
	-- Первый снапшот профиля (Data.ready) приходит скачком — уровень 1 -> 37,
	-- деньги 0 -> 5M: на это не празднуем, только на изменения после него.
	local prevLevel: number? = nil
	effect(function()
		local level = Data.level()
		local ready = Data.ready()
		untrack(function()
			if not ready then
				return
			end
			if prevLevel and level > prevLevel then
				local required = RebirthConfig.RequiredLevelForRebirth(Data.rebirths())
				pushBanner({ title = "LEVEL UP!", subtitle = "Level " .. level, color = GOLD, priority = 5 })
				if prevLevel < required and level >= required then
					pushBanner({
						title = "REBIRTH READY!",
						subtitle = "Rebirth for a permanent power & cash boost",
						color = Theme.Rebirth,
						priority = 6,
					})
				end
				flashScreen(GOLD, 0.35)
				juice.shake(0.35)
				juice.fovPunch(5, 0.45)
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					juice.burst(hrp.Position, GOLD, 50, { speed = 1.3, size = 1.5 })
				end
			end
			prevLevel = level
		end)
	end)

	-- Ребёрс: счётчик вырос после первого снапшота -> праздничный эффект + баннер
	local prevRebirths: number? = nil
	effect(function()
		local rebirths = Data.rebirths()
		local ready = Data.ready()
		untrack(function()
			if not ready then
				return
			end
			if prevRebirths and rebirths > prevRebirths then
				playRebirthEffect()
				sfx.play("LevelUP")
				juice.shake(0.25)
				juice.fovPunch(4, 0.5)
				pushBanner({
					title = "REBIRTH!",
					subtitle = "Rebirth " .. rebirths .. " — stronger than ever",
					color = Theme.RebirthBright,
					priority = 8,
				})
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					juice.burst(hrp.Position, Theme.Rebirth, 45, { speed = 1.2, size = 1.4 })
				end
			end
			prevRebirths = rebirths
		end)
	end)

	local prevMoney: any = nil
	local wasGoalReady = false
	effect(function()
		local money = Data.money()
		local ready = Data.ready()
		untrack(function()
			if not ready then
				return
			end
			if prevMoney ~= nil then
				local ok, gained = pcall(EtNum.me, money, prevMoney)
				if ok and gained then
					moneyToast(EtNum.sub(money, prevMoney))
				end
			end
			prevMoney = money

			-- «хватает на самый дорогой доступный магнит» — один раз на переход
			local key = topMagnetKey()
			local magnet = key and MagnetData[key]
			local goalReady = magnet ~= nil and EtNum.meeq(money, magnet.Price)
			if goalReady and not wasGoalReady then
				sfx.play("GoalReady")
				pushNotice({
					key = "magnet",
					title = "You can buy a new magnet!",
					subtitle = (magnet.Display or magnet.Name) .. " — visit the magnet shop",
					hold = 3.5,
					color = Theme.Electric, -- магнит
				})
			end
			wasGoalReady = goalReady
		end)
	end)

	--=== пресс: сбор денег (баннер о скрафченном предмете убран — на прокачанном
	-- прессе это до 5 предметов в секунду) ==================================
	table.insert(
		connections,
		PressService.MoneyCollected:Connect(function(amount)
			sfx.play("Collect")
			juice.shake(0.2)
			flashScreen(GREEN, 0.2)
			pushBanner({
				title = "+$" .. Format.short(amount),
				subtitle = "Collected from the press",
				color = GREEN,
				priority = 3,
			})
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				juice.burst(hrp.Position, GREEN, 40, { speed = 1.2, size = 1.3 })
			end
		end)
	)

	--=== Ore Merge: площадка Merge у пресса / кнопки Press Queue ====================
	-- Merge прошёл: баннер с итогом + лёгкая вспышка/тряска/частицы (без ослепления).
	-- «Nothing to merge» приходит отдельным уведомлением (Notice) — эффекта нет.
	local MERGE_COLOR = Theme.TealBright
	table.insert(
		connections,
		PressService.OreMerged:Connect(function(steps)
			local total = 0
			local last = steps[#steps]
			for _, step in ipairs(steps) do
				total += step.Groups
			end
			local subtitle = if #steps == 1
				then `{steps[1].Groups}x {steps[1].To}`
				else `{total} merges up to {last.To}`
			pushBanner({ title = "ORE MERGED!", subtitle = subtitle, color = MERGE_COLOR, priority = 4 })
			flashScreen(MERGE_COLOR, 0.2)
			juice.shake(0.2)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				juice.burst(hrp.Position, MERGE_COLOR, 40, { speed = 1.2, size = 1.3 })
			end
		end)
	)
	table.insert(
		connections,
		PressService.Notice:Connect(function(title: string, subtitle: string?)
			sfx.play("BagFull", { pitch = 1.4, volume = 0.5 })
			pushNotice({
				key = "press:" .. title,
				title = title,
				subtitle = subtitle,
				color = Theme.Warning,
				hold = 2,
			})
		end)
	)

	--=== авто-зона: нет доступа («Not enough rebirths», «Not Enough Yet»…) ===
	-- Сервер дебаунсит только одинаковые сообщения (AutoClickZoneHandler.MESSAGE_DEBOUNCE);
	-- каждое новое уведомление заменяет текущее и сбрасывает таймер. Показ короткий.
	table.insert(
		connections,
		AutoClickZoneService.ShowMessage:Connect(function(text: string, subtitle: string?)
			pushNotice({
				key = "zone:" .. text,
				title = text,
				subtitle = subtitle,
				color = RED,
				hold = ZONE_NOTICE_HOLD,
			})
		end)
	)

	return root
end

return FeedbackOverlay
