local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local LevelCurve = require(ReplicatedStorage.SharedSource.Datas.LevelCurve)
local ComboConfig = require(ReplicatedStorage.SharedSource.Datas.ComboConfig)
local ClickHandler = {}

---- Knit Services
local ClickerService
local PlayerManagerService

---- Datas
local TotalXPForLevel = LevelCurve.TotalForLevel

---- State
-- [player] = { combo, lastClick, windowStart, windowClicks } — только ручные клики.
local manualState = {}

-- Ручной клик: лимит частоты + комбо + крит. Возвращает (засчитан?, множитель, комбо, крит?).
local function registerManualClick(player): (boolean, number, number, boolean)
	local now = os.clock()
	local state = manualState[player]
	if not state then
		state = { combo = 0, lastClick = 0, windowStart = now, windowClicks = 0 }
		manualState[player] = state
	end

	if now - state.windowStart >= 1 then
		state.windowStart = now
		state.windowClicks = 0
	end
	state.windowClicks += 1
	if state.windowClicks > ComboConfig.MAX_CLICKS_PER_SECOND then
		return false, 1, state.combo, false
	end

	if now - state.lastClick <= ComboConfig.WINDOW then
		state.combo += 1
	else
		state.combo = 1
	end
	state.lastClick = now

	local multiplier = ComboConfig.Multiplier(state.combo)
	local crit = math.random() < ComboConfig.CRIT_CHANCE
	if crit then
		multiplier *= ComboConfig.CRIT_MULTIPLIER
	end
	return true, multiplier, state.combo, crit
end

---- Assets
-- extraMultiplier — доп. множитель поверх обычного клика (например, AutoClickZone.multiplier).
-- manual — клик игрока по экрану (комбо/криты/лимит частоты), а не автоудар/автозона.
-- Возвращает прирост силы за клик (EtNum-строка) или nil, если клик не засчитан.
function ClickHandler:Click(player, extraMultiplier: number?, manual: boolean?): string?
	extraMultiplier = extraMultiplier or 1

	local crit = false
	if manual then
		local accepted, comboMultiplier, _, isCrit = registerManualClick(player)
		if not accepted then
			return
		end
		extraMultiplier *= comboMultiplier
		crit = isCrit
	end

	local magnetism = ClickerService:GetPlayerMagnetism(player)
	local magnetMagnetism = PlayerManagerService:GetPlayerMagnet(player).Magnetism
	if not magnetism or not magnetMagnetism then
		return
	end

	-- множитель силы за ребёрсы: применяется к приросту силы за один клик
	local magnetismMultiplier = PlayerManagerService:GetPlayerMagnetismMultiplier(player) or 1
	-- бонус за друзей в сессии: +5% за каждого друга (см. FriendBonusHandler)
	local friendBonusMultiplier = PlayerManagerService:GetFriendBonusMultiplier(player) or 1
	local magnetismGain =
		EtNum.mul(EtNum.mul(EtNum.mul(magnetMagnetism, magnetismMultiplier), extraMultiplier), friendBonusMultiplier)

	local newMagnetism = EtNum.add(magnetism, magnetismGain)

	local currentLevel = ClickerService:GetPlayerLevel(player)
	local leveledUp = false

	while EtNum.meeq(newMagnetism, TotalXPForLevel(currentLevel + 1)) do
		currentLevel += 1
		leveledUp = true
	end

	if leveledUp then
		ClickerService:ChangePlayerLevel(player, currentLevel)
	end

	ClickerService:ChangePlayerMagnetism(player, EtNum.toString(newMagnetism))

	if crit then
		ClickerService.Client.CritClick:Fire(player, EtNum.toString(magnetismGain))
	end

	return EtNum.toString(magnetismGain)
end

function ClickHandler.Start() end

function ClickHandler.Init()
	ClickerService = Knit.GetService("ClickerService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerRemoving:Connect(function(player)
		manualState[player] = nil
	end)
end

return ClickHandler
