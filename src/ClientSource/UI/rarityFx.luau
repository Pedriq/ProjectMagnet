local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local source = vide.source

--[[
	rarityFx — общий «мотор» анимаций для эффектов редких мечей (RarityText / WeaponCard).

	`clock` — Vide-источник с монотонным временем в секундах, обновляется каждый
	Heartbeat. Читай его внутри биндинга свойства (`Offset = function() ... clock() ... end`)
	— биндинг будет пересчитываться каждый кадр. Пока эффектов на экране нет,
	у источника нет подписчиков и апдейт почти бесплатный.

	Ниже — чистые помощники для сборки ColorSequence/цветов эффектов.
]]

local rarityFx = {}

local t = 0
local clock = source(0)
rarityFx.clock = clock

RunService.Heartbeat:Connect(function(dt)
	t += dt
	clock(t)
end)

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

function rarityFx.lighten(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, math.clamp(amount, 0, 1))
end

function rarityFx.darken(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, math.clamp(amount, 0, 1))
end

-- Радужная ColorSequence, прокрученная по оттенку на `shift` (0..1). Периодична —
-- анимируй `shift` линейно и стык не будет виден.
function rarityFx.rainbowSequence(shift: number, saturation: number?, value: number?): ColorSequence
	local sat = saturation or 0.85
	local val = value or 1
	local steps = 8
	local kp = table.create(steps + 1)
	for i = 0, steps do
		local a = i / steps
		kp[i + 1] = ColorSequenceKeypoint.new(a, Color3.fromHSV((a + shift) % 1, sat, val))
	end
	return ColorSequence.new(kp)
end

-- Градиент `base` со светлым бликом в позиции `pos` (0..1) — двигай `pos`
-- туда-обратно, получится «перелив» по горизонтали.
function rarityFx.highlightSequence(base: Color3, hi: Color3, pos: number): ColorSequence
	local p = math.clamp(pos, 0.001, 0.999)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(math.max(p - 0.18, 0.0001), base),
		ColorSequenceKeypoint.new(p, hi),
		ColorSequenceKeypoint.new(math.min(p + 0.18, 0.9999), base),
		ColorSequenceKeypoint.new(1, base),
	})
end

-- Плавный цикл по «разным цветам» (для card-эффекта 2): непрерывный оборот оттенка.
function rarityFx.cycleColor(phase: number, saturation: number?, value: number?): Color3
	return Color3.fromHSV(phase % 1, saturation or 0.55, value or 0.95)
end

return rarityFx
