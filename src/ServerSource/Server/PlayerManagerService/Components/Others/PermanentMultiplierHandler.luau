local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PermanentMultiplierConfig = require(ReplicatedStorage.SharedSource.Datas.PermanentMultiplierConfig)

--[[
	PermanentMultiplierHandler — постоянные (на весь аккаунт) множители за донат:
	HUD -> BuffBuyButton. Источник правды — profile.PermanentMultipliers (см.
	ProfileTemplate), там же хранится текущий купленный множитель (0 = нет).

	В отличие от BuffHandler (временные баффы) — тут нет истечения по времени,
	просто число в профиле, и каждая следующая ступень ЗАМЕНЯЕТ (не складывает)
	предыдущую.
]]
local PermanentMultiplierHandler = {}

---- Knit Services
local ProfileService

function PermanentMultiplierHandler:GetOwnedMultiplier(player: Player, buffType: string): number
	return tonumber(ProfileService:GetData(player, { "PermanentMultipliers", buffType })) or 0
end

-- Бонус к итоговому множителю от текущей купленной ступени (0, если ничего не
-- куплено) — складывается с rebirth-множителем и бонусом временного баффа в
-- PlayerManagerService:GetPlayerCashMultiplier/GetPlayerStrengthMultiplier.
function PermanentMultiplierHandler:GetBonus(player: Player, buffType: string): number
	local owned = self:GetOwnedMultiplier(player, buffType)
	return owned > 0 and (owned - 1) or 0
end

-- Выдать ступень. ЗАМЕНЯЕТ текущую купленную (не складывается). tier.Multiplier
-- <= уже купленному — ступень устарела (например, повторная обработка чека
-- после того, как игрок уже купил более высокую) — тихо игнорируем, покупку
-- при этом всё равно считаем успешной (деньги уже списаны Roblox).
function PermanentMultiplierHandler:Grant(player: Player, buffType: string, tier: PermanentMultiplierConfig.Tier)
	local owned = self:GetOwnedMultiplier(player, buffType)
	if tier.Multiplier <= owned then
		return
	end

	ProfileService:ChangeData(player, { "PermanentMultipliers", buffType }, tier.Multiplier)
end

function PermanentMultiplierHandler.Start() end

function PermanentMultiplierHandler.Init()
	ProfileService = Knit.GetService("ProfileService")
end

return PermanentMultiplierHandler
