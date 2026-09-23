local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	BuffHandler — временные баффы к множителям (Magnetism / Money), см. BuffConfig.

	Кэшируется в памяти (PlayerManagerService.PlayerBuffs[userId][buffType]) для
	быстрого чтения в GetBonus, но ИСТОЧНИК ПРАВДЫ — profile.Buffs (ProfileService):
	туда пишется абсолютное время истечения (os.time()), так что бафф переживает
	выход/вход и рестарт сервера — см. Grant/RestorePlayer.

	Повторная покупка/выдача того же типа баффа ПРОДЛЕВАЕТ время (складывается
	с уже оставшимся), а не перезапускает таймер — см. Grant.

	Клиенту (и внутри GetBonus) время отдаётся как workspace:GetServerTimeNow()
	момент истечения (синхронизировано клиент/сервер, не зависит от системных
	часов игрока; тот же приём, что в TreasureBillboard) — RestorePlayer
	пересчитывает сохранённый os.time() в текущий workspace-момент при входе.
]]
local BuffHandler = {}

---- Knit Services
local PlayerManagerService
local ProfileService

local function buffsFor(userId: number)
	local buffs = PlayerManagerService.PlayerBuffs[userId]
	if not buffs then
		buffs = {}
		PlayerManagerService.PlayerBuffs[userId] = buffs
	end
	return buffs
end

-- Выдать/продлить бафф. durationSeconds добавляется к оставшемуся времени, если
-- бафф этого типа уже активен (иначе — от текущего момента).
function BuffHandler:Grant(player: Player, buffType: string, durationSeconds: number, bonus: number)
	local buffs = buffsFor(player.UserId)
	local now = Workspace:GetServerTimeNow()

	local current = buffs[buffType]
	local base = (current and current.ExpiresAt > now) and current.ExpiresAt or now
	local expiresAt = base + durationSeconds
	local remaining = expiresAt - now

	buffs[buffType] = { ExpiresAt = expiresAt, Bonus = bonus }

	-- os.time() — абсолютные часы, а не workspace-время (сбрасывается на
	-- каждом сервере) — так бафф можно восстановить после релога.
	ProfileService:ChangeData(player, { "Buffs", buffType }, { ExpiresAt = os.time() + remaining, Bonus = bonus })

	PlayerManagerService.Client.BuffChanged:Fire(player, buffType, expiresAt, bonus)
end

-- Восстановить активные баффы игрока из профиля при входе (см. вызов из
-- PlayerManagerService.KnitInit -> Players.PlayerAdded). Истёкшие записи
-- подчищаются из профиля.
function BuffHandler:RestorePlayer(player: Player)
	local profileBuffs = ProfileService:GetData(player, { "Buffs" })
	if not profileBuffs then
		return
	end

	local buffs = buffsFor(player.UserId)
	local sessionNow = Workspace:GetServerTimeNow()
	local wallNow = os.time()

	for buffType, entry in pairs(profileBuffs) do
		local remaining = (entry.ExpiresAt or 0) - wallNow
		if remaining > 0 then
			local expiresAt = sessionNow + remaining
			buffs[buffType] = { ExpiresAt = expiresAt, Bonus = entry.Bonus }
			PlayerManagerService.Client.BuffChanged:Fire(player, buffType, expiresAt, entry.Bonus)
		else
			ProfileService:ChangeData(player, { "Buffs", buffType }, nil)
		end
	end
end

-- Текущие активные баффы (уже без истёкших) — снапшот для клиента при старте
-- (см. PlayerManagerService.Client:GetActiveBuffs), т.к. BuffChanged из
-- RestorePlayer может прилететь раньше, чем клиент на него подпишется.
function BuffHandler:GetActiveBuffs(player: Player): { [string]: { ExpiresAt: number, Bonus: number } }
	local buffs = PlayerManagerService.PlayerBuffs[player.UserId]
	if not buffs then
		return {}
	end

	local now = Workspace:GetServerTimeNow()
	local active = {}
	for buffType, entry in pairs(buffs) do
		if entry.ExpiresAt > now then
			active[buffType] = entry
		end
	end
	return active
end

-- Текущий бонус к множителю этого типа (0, если баффа нет/истёк) — складывается
-- с базовым множителем за ребёрс в GetPlayer{Magnetism,Cash}Multiplier.
function BuffHandler:GetBonus(player: Player, buffType: string): number
	local buffs = PlayerManagerService.PlayerBuffs[player.UserId]
	local buff = buffs and buffs[buffType]
	if not buff then
		return 0
	end

	if buff.ExpiresAt <= Workspace:GetServerTimeNow() then
		return 0
	end

	return buff.Bonus
end

function BuffHandler.Start() end

function BuffHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ProfileService = Knit.GetService("ProfileService")
end

return BuffHandler
