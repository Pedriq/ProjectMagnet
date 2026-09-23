local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
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
	     PlayerWeaponHitboxManager:ApplyHit — срабатывает по таймеру
	     хитбокса, без привязки к экрану) — в случайной точке экрана.

	Прирост считается на клиенте по той же формуле, что и сервер (ClickHandler):
	  оружие * Data.fullStrengthMultiplier() * extraMultiplier
	Data.fullStrengthMultiplier() — rebirth-множитель + бонус активного
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
local GAIN_COLOR = Color3.fromRGB(255, 208, 1) -- как STRENGTH в RebirthPanel
local GAIN_RISE = 46 -- на сколько пикселей всплывает вверх
local GAIN_TIME = 0.7
local GAIN_GAP = RIPPLE_SIZE / 2 + 8 -- отступ пилюли над точкой/кольцом

-- отступы для случайных точек (удар/автозона), чтобы крупная пилюля не обрезалась краем экрана
local RANDOM_MARGIN_X = 90
local RANDOM_MARGIN_TOP = GAIN_RISE + 60
local RANDOM_MARGIN_BOTTOM = 40

local function isPointerClick(input: InputObject)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function computeGainText(multiplier: number?): string
	local weapon = Data.weapon()
	local gain = EtNum.mul(weapon.Strength, Data.fullStrengthMultiplier() * (multiplier or 1))
	return "+" .. Format.short(gain)
end

local function randomScreenPos(): (number, number)
	local camera = Workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)

	local maxX = math.max(RANDOM_MARGIN_X, viewport.X - RANDOM_MARGIN_X)
	local maxY = math.max(RANDOM_MARGIN_TOP, viewport.Y - RANDOM_MARGIN_BOTTOM)

	return math.random(RANDOM_MARGIN_X, maxX), math.random(RANDOM_MARGIN_TOP, maxY)
end

-- component для vide.indexes (удаление из карты уже отложено через spawnPop -> task.delay)
local function clickPop(item: () -> { x: number, y: number, gainText: string, withRing: boolean, large: boolean })
	local data = item()

	local iconSize = data.large and GAIN_ICON_SIZE_LARGE or GAIN_ICON_SIZE
	local textSize = data.large and GAIN_TEXT_SIZE_LARGE or GAIN_TEXT_SIZE
	local pillWidth = data.large and 160 or 120
	local labelHeight = data.large and 40 or 26

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
		TextColor3 = GAIN_COLOR,
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

	local pops =
		source({} :: { [number]: { x: number, y: number, gainText: string, withRing: boolean, large: boolean } })
	local nextId = 0

	local lifetime = math.max(RIPPLE_TIME, GAIN_TIME)

	local function spawnPop(x: number, y: number, gainText: string, withRing: boolean, large: boolean)
		nextId += 1
		local id = nextId

		local list = table.clone(pops())
		list[id] = { x = x, y = y, gainText = gainText, withRing = withRing, large = large }
		pops(list)

		task.delay(lifetime, function()
			local cur = table.clone(pops())
			cur[id] = nil
			pops(cur)
		end)
	end

	-- 1) обычный клик/тап мимо UI — в точке клика, с кольцом
	local inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		if gameProcessedEvent then
			return
		end

		if not isPointerClick(input) then
			return
		end

		-- ScreenGui рисуется с IgnoreGuiInset = true (абсолютные пиксели экрана),
		-- а input.Position уже уменьшен на высоту топбара — компенсируем инсет,
		-- иначе эффект оказывается выше реальной точки клика.
		local inset = GuiService:GetGuiInset()
		spawnPop(input.Position.X + inset.X, input.Position.Y + inset.Y, computeGainText(), true, false)
	end)

	-- 2) авто-удар оружия по камню — без привязки к экрану, случайная точка.
	-- AttackHit стреляет РОВНО 1 раз за взмах (в отличие от HitRock, который
	-- бьёт по каждому задетому стеблю — один взмах может задеть сразу несколько
	-- камней, но начисление силы за него одно).
	local hitConn = PlayerManagerService.AttackHit:Connect(function()
		local x, y = randomScreenPos()
		spawnPop(x, y, computeGainText(), false, true)
	end)

	cleanup(function()
		inputConn:Disconnect()
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
