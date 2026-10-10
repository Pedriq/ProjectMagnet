local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local juice = require(ReplicatedStorage.ClientSource.juice)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local perf = require(ReplicatedStorage.ClientSource.perf)

--[[
	HitFeedback — «сочность» удара по камню (только у локального игрока):
	  * цифра урона над камнем (крупнее, если удар снёс большую долю HP);
	  * полоска HP над камнем, пока по нему бьют;
	  * искры цвета руды, лёгкая тряска камеры;
	  * на добивании — взрыв искр и звук Shatter (без тряски камеры).

	Вызывается из RockController на каждый HitRock (visualData — запись из
	RockController.VisualizedRocks, см. RockVisualizer: Model, Section, Hp).
]]

local HitFeedback = {}

-- сколько живёт цифра урона (juice.worldText: time 0.8 + запас) — для учёта лимита perf.maxWorldTexts
local WORLD_TEXT_LIFETIME = 0.9
local activeTexts = 0

local HP_BAR_HIDE_AFTER = 1.6
local HP_BAR_SIZE = UDim2.fromOffset(110, 14)

local function oreColor(section: string?): Color3
	local ore = OreConfig.Get(section)
	return RarityColors.get(ore and ore.Rarity or section)
end

local function topOf(model: Model): Vector3
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2 + 0.6, 0)
end

local function ensureHpBar(visualData): BillboardGui
	local anchor = visualData.HpBar
	local existing = anchor and anchor.Parent and anchor:FindFirstChild("HpBar")
	if existing then
		return existing
	end

	local model: Model = visualData.Model

	-- Свой невидимый якорь, а не деталь модели: сегменты камня при откалывании
	-- улетают в игрока (VisualEffects:BreakSegment) — полоска улетела бы с ними.
	local anchor = Instance.new("Part")
	anchor.Name = "HpBarAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = topOf(model) + Vector3.new(0, 0.8, 0)
	anchor.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HpBar"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = HP_BAR_SIZE
	billboard.MaxDistance = 120
	billboard.Adornee = anchor

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 16, 26)
	back.BackgroundTransparency = 0.15
	back.Parent = billboard
	Instance.new("UICorner", back).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", back)
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)

	-- «догоняющая» белая полоска под основной — видно, сколько снёс удар
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.Size = UDim2.fromScale(1, 1)
	trail.BackgroundColor3 = Color3.new(1, 1, 1)
	trail.BorderSizePixel = 0
	trail.Parent = back
	Instance.new("UICorner", trail).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = oreColor(visualData.Section)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	billboard.Parent = anchor
	visualData.HpBar = anchor
	return billboard
end

local function updateHpBar(visualData, newHp: number, maxHp: number)
	if not visualData.Model or not visualData.Model.Parent then
		return
	end
	local billboard = ensureHpBar(visualData)
	billboard.Enabled = true

	local fraction = math.clamp(newHp / maxHp, 0, 1)
	local back = billboard.Back
	TweenService:Create(back.Fill, TweenInfo.new(0.08), { Size = UDim2.fromScale(fraction, 1) }):Play()
	TweenService:Create(
		back.Trail,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.15),
		{ Size = UDim2.fromScale(fraction, 1) }
	):Play()

	-- лёгкий «пинок» полоски на каждый удар
	billboard.Size = HP_BAR_SIZE + UDim2.fromOffset(12, 4)
	TweenService:Create(billboard, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Size = HP_BAR_SIZE }):Play()

	visualData.HpBarHideToken = (visualData.HpBarHideToken or 0) + 1
	local token = visualData.HpBarHideToken
	task.delay(HP_BAR_HIDE_AFTER, function()
		if visualData.HpBarHideToken == token and billboard.Parent then
			billboard.Enabled = false
		end
	end)
end

function HitFeedback:OnHit(visualData, maxHp: number, newHp: number)
	local model: Model? = visualData.Model
	if not model or not model.Parent or not maxHp or maxHp <= 0 then
		return
	end

	local prevHp = visualData.Hp or maxHp
	local dealt = math.max(prevHp - math.max(newHp, 0), 0)
	visualData.Hp = newHp

	local color = oreColor(visualData.Section)
	local top = topOf(model)
	local share = math.clamp(dealt / maxHp, 0, 1)

	-- На мобильных при массовом разрушении цифр не больше perf.maxWorldTexts одновременно
	if dealt > 0 and activeTexts < perf.maxWorldTexts then
		activeTexts += 1
		task.delay(WORLD_TEXT_LIFETIME, function()
			activeTexts -= 1
		end)
		juice.worldText(top, "-" .. Format.short(dealt), Color3.new(1, 1, 1):Lerp(color, 0.35), {
			-- studs: компактно над камнем, чуть крупнее при сильном ударе
			size = 0.9 + share * 0.4,
			rise = 1.8 + share * 0.8,
		})
	end
	juice.burst(
		top - Vector3.new(0, 0.8, 0),
		color,
		math.max(math.floor((6 + math.floor(share * 10)) * perf.burstScale), 1),
		{ size = 0.7 }
	)
	-- лёгкая тряска только на обычных ударах; добивающий удар камеру не трясёт
	if newHp > 0 then
		juice.shake(0.06 + share * 0.15)
	end

	if newHp <= 0 then
		self:OnShatter(visualData, top, color)
	else
		updateHpBar(visualData, newHp, maxHp)
	end
end

function HitFeedback:OnShatter(visualData, top: Vector3, color: Color3)
	if visualData.HpBar then
		visualData.HpBar:Destroy()
		visualData.HpBar = nil
	end

	-- без тряски камеры и FOV-удара на разрушении — только искры и звук
	juice.burst(top, color, math.floor(40 * perf.burstScale), { speed = 1.6, size = 1.4 })
	sfx.play("Shatter", { jitter = 0.06 })
end

function HitFeedback.Start() end

function HitFeedback.Init() end

return HitFeedback
