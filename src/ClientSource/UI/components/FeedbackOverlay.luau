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
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)

local create = vide.create
local effect = vide.effect
local cleanup = vide.cleanup
local untrack = vide.untrack

--[[
	FeedbackOverlay — слой обратной связи поверх HUD (отдельный ScreenGui, см. App):

	  * Баннеры (очередь, по одному): LEVEL UP, REBIRTH READY, рубежи комбо,
	    сбор денег с пресса, «хватает на магнит».
	  * Счётчик комбо ручного клика с убывающей полоской-таймером.
	  * BAG FULL: пульсирующее предупреждение, пока инвентарь переноски полон
	    (иначе игрок не понимает, почему магнит перестал бить камни).
	  * Уведомление «новый магнит доступен» — один раз, когда денег стало хватать.
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

-- Следующий магнит по порядку магазина, которым игрок ещё не владеет и который
-- продаётся за Money.
local function nextMagnetKey(): string?
	local owned = Data.ownedMagnets()
	for _, key in ipairs(MagnetData.Order) do
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
	bagAlert.Size = UDim2.fromOffset(520, 90)
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

	local bagPulse = 0
	local wasFull = false
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			local full = Data.ready() and isBagFull() and not WorldState.inSaveZone()
			if full ~= wasFull then
				wasFull = full
				bagAlert.Visible = full
				if full then
					sfx.play("BagFull")
					juice.shake(0.3)
					flashScreen(RED, 0.25)
				end
			end
			if full then
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

			-- «хватает на следующий магнит» — один раз на переход
			local key = nextMagnetKey()
			local magnet = key and MagnetData[key]
			local goalReady = magnet ~= nil and EtNum.meeq(money, magnet.Price)
			if goalReady and not wasGoalReady then
				sfx.play("GoalReady")
				pushBanner({
					title = "NEW MAGNET READY!",
					subtitle = (magnet.Display or magnet.Name) .. " — visit the magnet shop",
					color = Theme.Electric, -- магнит
					priority = 4,
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

	return root
end

return FeedbackOverlay
