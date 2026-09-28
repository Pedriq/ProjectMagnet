local MarketplaceService = game:GetService("MarketplaceService")

--[[
	AutoClickZonePlayerData — "Player Data Manager" из README.md.

	Владение донатными автоклик-зонами — через Game Pass. Источник правды —
	САМ ROBLOX (UserOwnsGamePassAsync), не наш профиль/DataStore: это снимает
	целый класс проблем с Developer Product + ProcessReceipt (недоставленный
	или задержанный чек, "заплатил — а зона не выдалась") — Game Pass либо
	куплен, либо нет, и Roblox хранит это сам и навсегда, без нашего участия.

	Кэш [userId][zoneId] = true — ТОЛЬКО чтобы не дёргать UserOwnsGamePassAsync
	(сетевой вызов с лимитами и задержкой) на каждый тик автоклика. Заполняется
	один раз при входе игрока (LoadForPlayer, асинхронно, параллельно по всем
	зонам) и точечно обновляется сразу на успешную покупку (MarkOwned, см.
	Purchase Manager -> PromptGamePassPurchaseFinished) — новый живой запрос не
	нужен, само событие уже подтверждено Roblox.

	IsOwned читает ТОЛЬКО кэш и никогда не yield'ит — безопасно звать из
	горячего тик-цикла Zone Manager. Refresh — единственный метод, который
	реально ходит в Roblox (yield), используется только по явному запросу
	игрока (кнопка "Купить" в Shop), не в тике.
]]
local AutoClickZonePlayerData = {}

local ownedCache: { [number]: { [string]: boolean } } = {} -- [userId][zoneId] = true

local function cacheFor(userId: number)
	local cache = ownedCache[userId]
	if not cache then
		cache = {}
		ownedCache[userId] = cache
	end
	return cache
end

-- Синхронно, без yield — безопасно для тик-цикла.
function AutoClickZonePlayerData:IsOwned(player: Player, zoneId: string): boolean
	local cache = ownedCache[player.UserId]
	return cache ~= nil and cache[zoneId] == true
end

-- Живой запрос к Roblox (yield) — на случай, если игрок купил пасс вне нашего
-- кэша (например, на другом сервере/со страницы игры) до того, как кэш успел
-- это подхватить. Использовать только вне горячего тик-цикла (например, перед
-- показом окна покупки в Shop).
function AutoClickZonePlayerData:Refresh(player: Player, zoneId: string, gamePassId: number): boolean
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)

	if not ok then
		warn(`[AutoClickZonePlayerData] UserOwnsGamePassAsync упал для {player.Name}, gamePassId={gamePassId}:`, owns)
		return self:IsOwned(player, zoneId)
	end

	if owns then
		cacheFor(player.UserId)[zoneId] = true
	end

	return owns
end

-- Отметить зону купленной БЕЗ похода в Roblox — сразу после подтверждённой
-- покупки (PromptGamePassPurchaseFinished уже сообщил wasPurchased = true,
-- повторный запрос не нужен).
function AutoClickZonePlayerData:MarkOwned(player: Player, zoneId: string)
	cacheFor(player.UserId)[zoneId] = true
end

-- Заполнить кэш для игрока при входе: параллельно (task.spawn на каждую зону)
-- запрашивает владение по ВСЕМ донат-зонам сразу, а не последовательно — иначе
-- N зон = N сетевых round-trip'ов подряд.
function AutoClickZonePlayerData:LoadForPlayer(player: Player, zones: { { ZoneId: string, GamePassId: number } })
	for _, zone in ipairs(zones) do
		task.spawn(function()
			self:Refresh(player, zone.ZoneId, zone.GamePassId)
		end)
	end
end

function AutoClickZonePlayerData:ClearPlayer(player: Player)
	ownedCache[player.UserId] = nil
end

function AutoClickZonePlayerData.Start() end
function AutoClickZonePlayerData.Init() end

return AutoClickZonePlayerData
