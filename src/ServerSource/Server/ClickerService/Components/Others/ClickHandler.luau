local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local LevelCurve = require(ReplicatedStorage.SharedSource.Datas.LevelCurve)
local ClickHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local ClickerService
local PlayerManagerService

---- Datas
local TotalXPForLevel = LevelCurve.TotalForLevel

---- Assets
-- extraMultiplier — доп. множитель поверх обычного клика (например, AutoClickZone.multiplier).
function ClickHandler:Click(player, extraMultiplier: number?)
	extraMultiplier = extraMultiplier or 1

	local str = ClickerService:GetPlayerStrength(player)
	local weaponStr = PlayerManagerService:GetPlayerWeapon(player).Strength
	if not str or not weaponStr then
		return
	end

	-- множитель силы за ребёрсы: применяется к приросту силы за один клик
	local strengthMultiplier = PlayerManagerService:GetPlayerStrengthMultiplier(player) or 1
	-- бонус за друзей в сессии: +5% за каждого друга (см. FriendBonusHandler)
	local friendBonusMultiplier = PlayerManagerService:GetFriendBonusMultiplier(player) or 1
	local strGain =
		EtNum.mul(EtNum.mul(EtNum.mul(weaponStr, strengthMultiplier), extraMultiplier), friendBonusMultiplier)

	local newStr = EtNum.add(str, strGain)

	local currentLevel = ClickerService:GetPlayerLevel(player)
	local leveledUp = false

	while EtNum.meeq(newStr, TotalXPForLevel(currentLevel + 1)) do
		currentLevel += 1
		leveledUp = true
	end

	if leveledUp then
		ClickerService:ChangePlayerLevel(player, currentLevel)
		-- Ивент на сервер для эффектов и прочей хуйни
	end

	ClickerService:ChangePlayerStrength(player, EtNum.toString(newStr))
	print(PlayerManagerService:GetAllPlayerData(player))
end

function ClickHandler.Start() end

function ClickHandler.Init()
	ClickerService = Knit.GetService("ClickerService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return ClickHandler
