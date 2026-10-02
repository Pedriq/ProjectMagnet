local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ComboConfig = require(ReplicatedStorage.SharedSource.Datas.ComboConfig)

--[[
	combo — клиентское зеркало комбо ручного клика (см. ComboConfig / ClickHandler).
	Сервер считает комбо сам по тем же правилам — тут оно только для UI/звука.

	  combo.count()       — Vide-источник: текущее комбо (0 — нет)
	  combo.timeLeft()    — Vide-источник: 0..1, сколько осталось до сгорания
	  combo.Clicked       — Signal(x, y, count): ручной клик по миру засчитан;
	                        x/y — экранные пиксели (с учётом GuiInset), nil у геймпада
	  combo.Milestone     — Signal(count): достигнут рубеж ComboConfig.MILESTONES
	  combo.Dropped       — Signal(count): комбо сгорело (count — каким было)
	  combo.register(x?, y?) — вызывает ClickerController на каждый ручной клик
]]

local combo = {}

combo.count = vide.source(0)
combo.timeLeft = vide.source(0)
combo.Clicked = Signal.new()
combo.Milestone = Signal.new()
combo.Dropped = Signal.new()

local lastClick = 0
local windowStart = 0
local windowClicks = 0

function combo.register(x: number?, y: number?)
	local now = os.clock()

	-- тот же лимит частоты, что на сервере — чтобы клиент не насчитал лишнего
	if now - windowStart >= 1 then
		windowStart = now
		windowClicks = 0
	end
	windowClicks += 1
	if windowClicks > ComboConfig.MAX_CLICKS_PER_SECOND then
		return
	end

	local count = if now - lastClick <= ComboConfig.WINDOW then combo.count() + 1 else 1
	lastClick = now
	combo.count(count)
	combo.timeLeft(1)

	combo.Clicked:Fire(x, y, count)
	if table.find(ComboConfig.MILESTONES, count) then
		combo.Milestone:Fire(count)
	end
end

-- Прирост силы ручного клика с учётом комбо — для превью в ClickEffect.
function combo.multiplier(): number
	return ComboConfig.Multiplier(combo.count())
end

RunService.Heartbeat:Connect(function()
	local count = combo.count()
	if count == 0 then
		return
	end
	local left = 1 - (os.clock() - lastClick) / ComboConfig.WINDOW
	if left <= 0 then
		combo.count(0)
		combo.timeLeft(0)
		combo.Dropped:Fire(count)
	else
		combo.timeLeft(left)
	end
end)

return combo
