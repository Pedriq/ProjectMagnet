local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Knit = require(ReplicatedStorage.Packages.Knit)

local source = vide.source

--[[
	offline — состояние окна офлайн-наград (Welcome Back).

	Reward — nil или { Money, Magnetism, Seconds, Away, Capped } (EtNum-строки/секунды). Всё считает и
	выдаёт сервер (OfflineService): клиент только спрашивает награду после старта и просит её забрать.

	Окно открывается ровно тогда, когда выполнены ОБА условия: сервер вернул награду И экран загрузки
	закончился (loadingFinished из InitPlayerUI) — в любом порядке. Размытие фона и отдаление камеры
	окну даёт тот же механизм, что и остальным панелям (screens/HUD: effect по openPanel / Offline.reward).
]]
local Offline = {}

Offline.reward = source(nil :: any)

local started = false
local claiming = false
local loadingDone = false
local queued: any = nil -- награда пришла, ждёт конца экрана загрузки

local function tryShow()
	if queued ~= nil and loadingDone then
		Offline.reward(queued)
		queued = nil
	end
end

-- Экран загрузки погас: можно показывать награду.
function Offline.loadingFinished()
	loadingDone = true
	tryShow()
end

function Offline.start()
	if started then
		return
	end
	started = true

	Knit.GetService("OfflineService").RewardReady:Connect(function(pending)
		queued = pending
		tryShow()
	end)

	task.spawn(function()
		local service = Knit.GetService("OfflineService")
		local ok, pending = service:GetPending():await()
		if not ok or type(pending) ~= "table" then
			return
		end
		queued = pending
		tryShow()
	end)
end

-- Забрать награду. Окно закрывается после ответа сервера (отказ — тоже закрывает: забирать нечего).
function Offline.claim()
	if claiming or Offline.reward() == nil then
		return
	end
	claiming = true
	Knit.GetService("OfflineService")
		:Claim()
		:andThen(function()
			Offline.reward(nil)
		end)
		:catch(warn)
		:finally(function()
			claiming = false
		end)
end

-- Закрыть без получения: награда остаётся в профиле, окно появится при следующем заходе.
function Offline.dismiss()
	queued = nil
	Offline.reward(nil)
end

return Offline
