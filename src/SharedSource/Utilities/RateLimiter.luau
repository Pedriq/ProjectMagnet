local Players = game:GetService("Players")

--[[
	RateLimiter — серверный лимит частоты вызовов клиентских методов (Knit Client:* / сигналов).

	Клиент — чужой код: эксплойтер может вызвать любой метод тысячи раз в секунду (спам промптов покупки,
	походов в UserOwnsGamePassAsync, пересчётов пресса, рассылки репликации). Каждый такой метод на сервере
	начинается с RateLimiter.Allow(player, "ИмяМетода", интервал) и молча отбрасывает лишние вызовы.

	  RateLimiter.Allow(player, key, interval) -> boolean
	    true — вызов можно выполнять (и время последнего вызова запомнено); false — слишком часто.
	    Ключ отдельный на каждый метод, поэтому разные методы друг другу не мешают.

	Состояние чистится при выходе игрока.
]]
local RateLimiter = {}

local last: { [number]: { [string]: number } } = {}
local connected = false

local function connectCleanup()
	connected = true
	Players.PlayerRemoving:Connect(function(player)
		last[player.UserId] = nil
	end)
end

function RateLimiter.Allow(player: Player, key: string, interval: number): boolean
	if not connected then
		connectCleanup()
	end

	local userId = player.UserId
	local keys = last[userId]
	if not keys then
		keys = {}
		last[userId] = keys
	end

	local now = os.clock()
	local previous = keys[key]
	if previous and now - previous < interval then
		return false
	end

	keys[key] = now
	return true
end

return RateLimiter
