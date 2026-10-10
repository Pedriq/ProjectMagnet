local UserInputService = game:GetService("UserInputService")

--[[
	perf — флаги и бюджеты производительности клиента. На ПК всё как раньше
	(isMobile = false, лимитов нет); на телефонах/планшетах эффекты массового
	разрушения камней урезаются, чтобы бег по полю не давал лагов.
]]

local perf = {}

-- Только сенсорное устройство без клавиатуры (как и в FeedbackOverlay/tutorial).
perf.isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Одновременно летящих в игрока кусочков (остальные просто исчезают — руда
-- начисляется сервером независимо от визуала).
perf.maxFlying = if perf.isMobile then 48 else math.huge
-- Одновременных цифр урона над камнями.
perf.maxWorldTexts = if perf.isMobile then 4 else math.huge
-- Сколько визуалов камней создавать за кадр (целая полоса появляется разом).
perf.rockVisualsPerFrame = if perf.isMobile then 2 else math.huge
-- Доля искр от значения на ПК.
perf.burstScale = if perf.isMobile then 0.4 else 1

return perf
