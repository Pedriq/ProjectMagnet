local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local OfflineConfig = require(ReplicatedStorage.SharedSource.Datas.OfflineConfig)
local RateLimiter = require(ReplicatedStorage.SharedSource.Utilities.RateLimiter)

--[[
	OfflineService — награда за время, проведённое вне игры.

	  * Выход: ProfileService пишет Offline.LastSeen = os.time() прямо перед EndSession.
	  * Вход (ProfileService.ProfileLoaded): отсутствие = now - LastSeen. LastSeen == 0 (первая сессия) —
	    награды нет. Сразу же LastSeen = now, поэтому повторный заход не посчитает то же время дважды.
	    Период награды ограничен OfflineConfig.MAX_OFFLINE_SECONDS.
	  * Пресс: PressService:SimulateOffline переплавляет руду из очереди за период (ту же логику,
	    скорость и множитель денег, что и онлайн) -> деньги в Offline.Money.
	  * Клики: 1 клик в CLICK_INTERVAL секунд; сила за клик = сила магнита * текущий множитель силы
	    (без комбо/критов/бонуса друзей), считается в момент Claim.
	  * Неполученная награда лежит в профиле (Offline.*) и не пропадёт, если игрок вышел, не нажав Claim;
	    при следующем заходе новая награда суммируется, период по-прежнему ограничен потолком.
	  * Claim: сначала обнуляет Offline.* (до любых выдач), потом выдаёт — двойная выдача невозможна.

	Ничего не крутится в цикле: всё по событиям (вход профиля, запрос клиента, Claim).
]]
local OfflineService = Knit.CreateService({
	Name = "OfflineService",
	Client = {
		-- Fire(player, pending) — награда появилась уже после старта UI (только тест-команда /offline).
		RewardReady = Knit.CreateSignal(),
	},
})

---- Knit Services
local ProfileService
local PressService
local PlayerManagerService
local ClickerService

local ready: { [Player]: boolean } = {} -- расчёт за отсутствие для игрока завершён
local READY_TIMEOUT = 30
local DEBUG = game:GetService("RunService"):IsStudio() -- в Studio пишем в Output, почему награды нет / сколько вышло

-- Сила, которую дадут `seconds` секунд симулируемых кликов, или nil, если кликов/магнита нет.
function OfflineService:_ComputeMagnetism(player, seconds: number): string?
	local clicks = OfflineConfig.ClicksFor(seconds)
	if clicks <= 0 then
		return nil
	end
	local equipped = PlayerManagerService:GetPlayerMagnet(player)
	local perClick = equipped and equipped.Magnetism
	if not perClick then
		return nil
	end
	local multiplier = PlayerManagerService:GetPlayerMagnetismMultiplier(player) or 1
	return EtNum.toString(EtNum.mul(EtNum.mul(perClick, multiplier), clicks))
end

function OfflineService:_OnProfileLoaded(player, fakeAway: number?)
	local offline = ProfileService:GetData(player, { "Offline" })
	if not offline then
		warn("[OfflineService] profile has no Offline table for", player.Name)
		return
	end

	local now = os.time()
	local lastSeen = if fakeAway then now - fakeAway else (tonumber(offline.LastSeen) or 0)
	-- сразу фиксируем вход: этот же интервал больше никогда не будет засчитан второй раз
	ProfileService:ChangeData(player, { "Offline", "LastSeen" }, now)

	local away = now - lastSeen
	if DEBUG then
		print(
			string.format(
				"[Offline] %s: LastSeen=%d away=%ds (min %d) %s",
				player.Name,
				lastSeen,
				if lastSeen > 0 then away else 0,
				OfflineConfig.MIN_AWAY_SECONDS,
				if lastSeen > 0 then "" else "-> первая сессия или профиль не сохранялся: награды нет"
			)
		)
	end
	if lastSeen > 0 and away >= OfflineConfig.MIN_AWAY_SECONDS then
		local rewardSeconds = math.min(away, OfflineConfig.MAX_OFFLINE_SECONDS)
		local money = PressService:SimulateOffline(player, rewardSeconds)

		local pendingMoney = ProfileService:GetData(player, { "Offline", "Money" }) or "0"
		local pendingSeconds = tonumber(ProfileService:GetData(player, { "Offline", "Seconds" })) or 0
		local pendingAway = tonumber(ProfileService:GetData(player, { "Offline", "Away" })) or 0

		ProfileService:ChangeData(player, { "Offline", "Money" }, EtNum.toString(EtNum.add(pendingMoney, money)))
		ProfileService:ChangeData(
			player,
			{ "Offline", "Seconds" },
			math.min(pendingSeconds + rewardSeconds, OfflineConfig.MAX_OFFLINE_SECONDS)
		)
		ProfileService:ChangeData(player, { "Offline", "Away" }, pendingAway + away)
	end

	ready[player] = true
end

-- Текущая неполученная награда или nil, если забирать нечего.
function OfflineService:GetPending(player)
	local offline = ProfileService:GetData(player, { "Offline" })
	if not offline then
		return nil
	end

	local money = offline.Money or "0"
	local seconds = tonumber(offline.Seconds) or 0
	local magnetism = self:_ComputeMagnetism(player, seconds)
	local hasMoney = EtNum.me(money, "0")
	if not hasMoney and not magnetism then
		return nil
	end

	return {
		Money = money,
		Magnetism = magnetism or "0",
		Seconds = seconds,
		Away = tonumber(offline.Away) or seconds,
		Capped = (tonumber(offline.Away) or 0) > seconds,
	}
end

function OfflineService:Claim(player): boolean
	if not ready[player] then
		return false
	end
	local pending = self:GetPending(player)
	if not pending then
		return false
	end

	-- обнуляем ДО выдачи: ни повторный Claim, ни перезаход не выдадут то же самое ещё раз
	ProfileService:ChangeData(player, { "Offline", "Money" }, "0")
	ProfileService:ChangeData(player, { "Offline", "Seconds" }, 0)
	ProfileService:ChangeData(player, { "Offline", "Away" }, 0)

	if EtNum.me(pending.Money, "0") then
		local money = PlayerManagerService:GetPlayerMoney(player) or "0"
		PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.add(pending.Money, money)))
	end
	if pending.Magnetism ~= "0" then
		ClickerService.Components.ClickHandler:GrantMagnetism(player, pending.Magnetism)
	end
	return true
end

-- Клиент спрашивает награду после старта UI. Ждём, пока загрузится профиль и посчитается отсутствие.
function OfflineService.Client:GetPending(player)
	if not RateLimiter.Allow(player, "OfflineGetPending", 2) then
		return nil
	end
	local deadline = os.clock() + READY_TIMEOUT
	while not ready[player] and player.Parent and os.clock() < deadline do
		task.wait(0.25)
	end
	if not ready[player] then
		return nil
	end
	return self.Server:GetPending(player)
end

function OfflineService.Client:Claim(player)
	if not RateLimiter.Allow(player, "OfflineClaim", 1) then
		return false
	end
	return self.Server:Claim(player)
end

-- ТОЛЬКО Studio (TestCommandsHandler, /offline <секунд>): как будто игрока не было `seconds` секунд.
function OfflineService:Simulate(player, seconds: number)
	if not DEBUG or not ready[player] then
		return
	end
	self:_OnProfileLoaded(player, seconds)
	local pending = self:GetPending(player)
	print("[Offline] pending:", pending)
	if pending then
		self.Client.RewardReady:Fire(player, pending)
	end
end

function OfflineService:KnitStart()
	ProfileService.ProfileLoaded:Connect(function(player)
		local ok, err = pcall(self._OnProfileLoaded, self, player)
		if not ok then
			warn("[OfflineService] offline calc failed:", err)
			ready[player] = true
		end
	end)

	-- профили, загрузившиеся до подписки
	for _, player in ipairs(Players:GetPlayers()) do
		if ProfileService.Profiles[player] and not ready[player] then
			task.spawn(self._OnProfileLoaded, self, player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
	end)
end

function OfflineService:KnitInit()
	ProfileService = Knit.GetService("ProfileService")
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ClickerService = Knit.GetService("ClickerService")
end

return OfflineService
