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

-- Точное значение множителя текущей купленной ступени (x2 -> 2; 0, если ничего не
-- куплено) — слагаемое суммы множителей в
-- PlayerManagerService:GetPlayerCashMultiplier/GetPlayerMagnetismMultiplier.
function PermanentMultiplierHandler:GetMultiplier(player: Player, buffType: string): number
	return self:GetOwnedMultiplier(player, buffType)
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
