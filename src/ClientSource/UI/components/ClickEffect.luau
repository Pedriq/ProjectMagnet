local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local combo = require(ReplicatedStorage.ClientSource.combo)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local source = vide.source
local indexes = vide.indexes
local cleanup = vide.cleanup

--[[
	ClickEffect — показывает "иконка сверху / число прироста силы снизу"
	(+ кольцо-пинг) на два источника прироста силы:

	  1) обычный клик/тап мимо UI — в точке клика (с кольцом).
	  2) авто-удар оружия по камню (PlayerManagerService.HitRock,
	     PlayerMagnetHitboxManager:ApplyHit — срабатывает по таймеру
	     хитбокса, без привязки к экрану) — в случайной точке экрана.

	Прирост считается на клиенте по той же формуле, что и сервер (ClickHandler):
	  оружие * Data.fullMagnetismMultiplier() * extraMultiplier
	Data.fullMagnetismMultiplier() — rebirth-множитель + бонус активного
	временного баффа + бонус постоянного донат-множителя (см. data.luau).
	Это лишь превью для UI — авторитетное значение считает сервер.
]]

local RIPPLE_SIZE = 54
local RIPPLE_GROW = 1.9
local RIPPLE_TIME = 0.45
local RIPPLE_COLOR = Color3.fromRGB(255, 255, 255)

local GAIN_ICON = "rbxassetid://96772289336842"
local GAIN_ICON_SIZE = 30
local GAIN_TEXT_SIZE = 20
-- крупнее для попапов без привязки к клику (удар/автозона) — их видно не под курсором,
-- поэтому глаз должен цеплять их сам
local GAIN_ICON_SIZE_LARGE = 48
local GAIN_TEXT_SIZE_LARGE = 32
local GAIN_COLOR = Color3.fromRGB(255, 208, 1) -- как MAGNETISM в RebirthPanel
local GAIN_RISE = 46 -- на сколько пикселей всплывает вверх
local GAIN_TIME = 0.7
local GAIN_GAP = RIPPLE_SIZE / 2 + 8 -- отступ пилюли над точкой/кольцом

-- отступы для случайных точек (удар/автозона), чтобы крупная пилюля не обрезалась краем экрана
local RANDOM_MARGIN_X = 90
local RANDOM_MARGIN_TOP = GAIN_RISE + 60
local RANDOM_MARGIN_BOTTOM = 40

-- крит (сигнал сервера ClickerService.CritClick) — крупно, красно-оранжевым
local CRIT_COLOR = Color3.fromRGB(255, 84, 46)
-- цвет попапа клика «накаляется» с комбо: жёлтый -> оранжевый -> малиновый
local COMBO_HOT_COLOR = Color3.fromRGB(255, 70, 140)
local COMBO_HOT_AT = 60

local function computeGainText(multiplier: number?): string
	local magnet = Data.magnet()
	local gain = EtNum.mul(magnet.Magnetism, Data.fullMagnetismMultiplier() * (multiplier or 1))
	return "+" .. Format.short(gain)
end

local function comboColor(count: number): Color3
	return GAIN_COLOR:Lerp(COMBO_HOT_COLOR, math.clamp(count / COMBO_HOT_AT, 0, 1))
end

local function randomScreenPos(): (number, number)
	local camera = Workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)

	local maxX = math.max(RANDOM_MARGIN_X, viewport.X - RANDOM_MARGIN_X)
	local maxY = math.max(RANDOM_MARGIN_TOP, viewport.Y - RANDOM_MARGIN_BOTTOM)

	return math.random(RANDOM_MARGIN_X, maxX), math.random(RANDOM_MARGIN_TOP, maxY)
end

-- component для vide.indexes (удаление из карты уже отложено через spawnPop -> task.delay)
type Pop = {
	x: number,
	y: number,
	gainText: string,
	withRing: boolean,
	large: boolean,
	color: Color3?,
	scale: number?, -- доп. масштаб (комбо/крит)
}

local function clickPop(item: () -> Pop)
	local data = item()
	local scale = data.scale or 1

	local iconSize = math.floor((data.large and GAIN_ICON_SIZE_LARGE or GAIN_ICON_SIZE) * scale)
	local textSize = math.floor((data.large and GAIN_TEXT_SIZE_LARGE or GAIN_TEXT_SIZE) * scale)
	local pillWidth = math.floor((data.large and 160 or 120) * scale)
	local labelHeight = math.floor((data.large and 40 or 26) * scale)

	local kids = {}

	--=== кольцо (только для настоящего клика/тапа по экрану) ===
	if data.withRing then
		local ringStroke = create("UIStroke")({
			Color = RIPPLE_COLOR,
			Thickness = 2,
			Transparency = 0.15,
		}) :: UIStroke

		local ring = create("Frame")({
			Name = "Ripple",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(data.x, data.y),
			Size = UDim2.fromOffset(RIPPLE_SIZE, RIPPLE_SIZE),
			BackgroundColor3 = RIPPLE_COLOR,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 50,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			ringStroke,
		}) :: Frame

		TweenService:Create(ring, TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(RIPPLE_SIZE * RIPPLE_GROW, RIPPLE_SIZE * RIPPLE_GROW),
			BackgroundTransparency = 1,
		}):Play()

		TweenService:Create(ringStroke, TweenInfo.new(RIPPLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()

		table.insert(kids, ring)
	end

	--=== пилюля прироста: иконка сверху, число снизу ===
	local textStroke = create("UIStroke")({
		Color = Color3.new(0, 0, 0),
		Thickness = 2,
		Transparency = 0,
	}) :: UIStroke

	local icon = create("ImageLabel")({
		Name = "Icon",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(iconSize, iconSize),
		BackgroundTransparency = 1,
		Image = GAIN_ICON,
		ImageTransparency = 0,
	}) :: ImageLabel

	local label = create("TextLabel")({
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(pillWidth, labelHeight),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = textSize,
		TextColor3 = data.color or GAIN_COLOR,
		TextTransparency = 0,
		Text = data.gainText,

		textStroke,
	}) :: TextLabel

	local startY = data.y - GAIN_GAP
	local endY = startY - GAIN_RISE

	local pill = create("Frame")({
		Name = "GainPopup",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(data.x, startY),
		Size = UDim2.fromOffset(pillWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 51,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 2),
		}),

		icon,
		label,
	}) :: Frame

	TweenService:Create(pill, TweenInfo.new(GAIN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(data.x, endY),
	}):Play()

	local fadeInfo =
		TweenInfo.new(GAIN_TIME - 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.15)
	TweenService:Create(icon, fadeInfo, { ImageTransparency = 1 }):Play()
	TweenService:Create(label, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(textStroke, fadeInfo, { Transparency = 1 }):Play()

	-- крупные (крит/высокое комбо) выскакивают с «пружиной»
	if scale > 1 then
		local pop = Instance.new("UIScale")
		pop.Scale = 1.6
		pop.Parent = pill
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	table.insert(kids, pill)

	return create("Frame")({
		Name = "ClickPop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		table.unpack(kids),
	}) :: Frame
end

local function ClickEffect()
	local PlayerManagerService = Knit.GetService("PlayerManagerService")

	local ClickerService = Knit.GetService("ClickerService")

	local pops = source({} :: { [number]: Pop })
	local nextId = 0

	local lifetime = math.max(RIPPLE_TIME, GAIN_TIME)

	-- последняя точка ручного клика — туда же падает попап крита (сигнал сервера
	-- приходит с задержкой пинга, к этому моменту палец обычно ещё там же)
	local lastClickX, lastClickY = nil :: number?, nil :: number?

	local function spawnPop(pop: Pop)
		nextId += 1
		local id = nextId

		local list = table.clone(pops())
		list[id] = pop
		pops(list)

		task.delay(lifetime, function()
			local cur = table.clone(pops())
			cur[id] = nil
			pops(cur)
		end)
	end

	-- 1) ручной клик/тап мимо UI — в точке клика, с кольцом. Засчитанный клик
	-- приходит из combo (его регистрирует ClickerController), поэтому прирост
	-- уже учитывает текущее комбо.
	local clickConn = combo.Clicked:Connect(function(x: number?, y: number?, count: number)
		if not x or not y then
			x, y = randomScreenPos()
		end
		lastClickX, lastClickY = x, y
		spawnPop({
			x = x :: number,
			y = y :: number,
			gainText = computeGainText(combo.multiplier()),
			withRing = true,
			large = false,
			color = comboColor(count),
			scale = 1 + math.min(count, 100) / 250,
		})
	end)

	-- 2) крит ручного клика (сервер прислал реальный прирост)
	local critConn = ClickerService.CritClick:Connect(function(gain: string)
		local x, y = lastClickX, lastClickY
		if not x or not y then
			x, y = randomScreenPos()
		end
		spawnPop({
			x = x :: number,
			y = (y :: number) - 30,
			gainText = "CRIT! +" .. Format.short(gain),
			withRing = false,
			large = true,
			color = CRIT_COLOR,
			scale = 1.25,
		})
	end)

	-- 3) авто-удар оружия по камню — без привязки к экрану, случайная точка.
	-- AttackHit стреляет РОВНО 1 раз за взмах (в отличие от HitRock, который
	-- бьёт по каждому задетому стеблю — один взмах может задеть сразу несколько
	-- камней, но начисление силы за него одно).
	local hitConn = PlayerManagerService.AttackHit:Connect(function()
		local x, y = randomScreenPos()
		spawnPop({ x = x, y = y, gainText = computeGainText(), withRing = false, large = true })
	end)

	cleanup(function()
		clickConn:Disconnect()
		critConn:Disconnect()
		hitConn:Disconnect()
	end)

	return create("Frame")({
		Name = "ClickEffect",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		indexes(pops, clickPop),
	})
end

return ClickEffect
