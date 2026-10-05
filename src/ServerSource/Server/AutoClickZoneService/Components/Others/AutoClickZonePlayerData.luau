local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	AutoClickZonePlayerData — "Player Data Manager" из README.md.

	Владение донатными автоклик-зонами — через Game Pass. Два источника, любой из них
	значит «куплено» (объединяются):
	  1. Roblox (UserOwnsGamePassAsync) — источник правды для живой игры;
	  2. профиль игрока (profile.AutoClickZones[zoneId] = true) — копия, которую мы
	     пишем сами при подтверждённой покупке и при подтверждении Roblox'ом. Нужна,
	     чтобы покупка переживала перезапуск, даже когда Roblox не отдаёт владение
	     (тест-покупки в Studio / Client+Server: PromptGamePassPurchaseFinished
	     приходит, а UserOwnsGamePassAsync после рестарта возвращает false) и когда
	     сетевой вызов упал.

	Кэш [userId][zoneId] = true — ТОЛЬКО чтобы не дёргать UserOwnsGamePassAsync
	(сетевой вызов с лимитами и задержкой) на каждый тик автоклика.

	ВАЖНО — «загружено ли»: кэш заполняется асинхронно после входа игрока (профиль +
	запросы в Roblox). Пока загрузка не закончена, зона может казаться «не куплена»
	просто потому, что кэш ещё пуст — раньше из-за этого окно покупки всплывало у уже
	купленных зон и пропадало у других в зависимости от скорости загрузки. Поэтому
	IsLoaded/WaitUntilLoaded: Zone Manager не принимает решений по игроку, пока
	загрузка не завершена.

	IsOwned читает ТОЛЬКО кэш и никогда не yield'ит — безопасно звать из
	горячего тик-цикла Zone Manager. Refresh — реально ходит в Roblox (yield),
	используется при загрузке и перед показом окна покупки, не в тике.
]]
local AutoClickZonePlayerData = {}

---- Knit Services
local ProfileService

local LOAD_ATTEMPTS = 3 -- попыток UserOwnsGamePassAsync на зону при входе
local LOAD_RETRY_DELAY = 1.5 -- секунд между попытками (растёт)

local ownedCache: { [number]: { [string]: boolean } } = {} -- [userId][zoneId] = true
local loaded: { [number]: boolean } = {} -- [userId] = первичная загрузка завершена
local loading: { [number]: boolean } = {} -- [userId] = загрузка идёт прямо сейчас

local function cacheFor(userId: number)
	local cache = ownedCache[userId]
	if not cache then
		cache = {}
		ownedCache[userId] = cache
	end
	return cache
end

-- Записать покупку в профиль (сохраняется вместе с остальными данными игрока).
local function persist(player: Player, zoneId: string)
	local ok, stored = pcall(function()
		return ProfileService:GetData(player, { "AutoClickZones", zoneId })
	end)
	if ok and stored == true then
		return
	end
	local saved, err = pcall(function()
		ProfileService:ChangeData(player, { "AutoClickZones", zoneId }, true)
	end)
	if not saved then
		warn(`[AutoClickZonePlayerData] не удалось сохранить зону {zoneId} в профиль {player.Name}:`, err)
	end
end

-- Синхронно, без yield — безопасно для тик-цикла.
function AutoClickZonePlayerData:IsOwned(player: Player, zoneId: string): boolean
	local cache = ownedCache[player.UserId]
	return cache ~= nil and cache[zoneId] == true
end

function AutoClickZonePlayerData:IsLoaded(player: Player): boolean
	return loaded[player.UserId] == true
end

-- Ждать конца первичной загрузки (yield). false — таймаут или игрок вышел.
function AutoClickZonePlayerData:WaitUntilLoaded(player: Player, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 10)
	while not loaded[player.UserId] do
		if not player.Parent or os.clock() > deadline then
			return false
		end
		task.wait(0.1)
	end
	return true
end

-- Живой запрос к Roblox (yield) — на случай, если игрок купил пасс вне нашего
-- кэша (например, на другом сервере/со страницы игры) до того, как кэш успел
-- это подхватить. Использовать только вне горячего тик-цикла (при загрузке и
-- перед показом окна покупки).
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
		persist(player, zoneId)
	end

	-- Roblox мог не знать про тест-покупку (Studio) — тогда решает кэш/профиль
	return owns or self:IsOwned(player, zoneId)
end

-- Отметить зону купленной БЕЗ похода в Roblox — сразу после подтверждённой
-- покупки (PromptGamePassPurchaseFinished уже сообщил wasPurchased = true,
-- повторный запрос не нужен). Сохраняется в профиль.
function AutoClickZonePlayerData:MarkOwned(player: Player, zoneId: string)
	cacheFor(player.UserId)[zoneId] = true
	task.spawn(persist, player, zoneId)
end

-- Заполнить кэш для игрока при входе: сначала профиль (мгновенно, без сети), потом
-- параллельно (task.spawn на каждую зону) Roblox с повторами при ошибке. Только после
-- того как ВСЕ зоны отработали, игрок помечается загруженным (IsLoaded).
-- Повторный вызов для того же игрока, пока загрузка идёт, игнорируется.
function AutoClickZonePlayerData:LoadForPlayer(player: Player, zones: { { ZoneId: string, GamePassId: number } })
	local userId = player.UserId
	if loading[userId] or loaded[userId] then
		return
	end
	loading[userId] = true

	task.spawn(function()
		-- 1) профиль: сюда попадают и тест-покупки, и всё, что уже подтверждал Roblox
		local okData, saved = pcall(function()
			return ProfileService:GetData(player, { "AutoClickZones" })
		end)
		if okData and type(saved) == "table" then
			local cache = cacheFor(userId)
			for zoneId, owned in pairs(saved) do
				if owned == true then
					cache[zoneId] = true
				end
			end
		end

		-- 2) Roblox: параллельно по зонам, с повторами
		local pending = #zones
		for _, zone in ipairs(zones) do
			task.spawn(function()
				for attempt = 1, LOAD_ATTEMPTS do
					if not player.Parent then
						break
					end
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(userId, zone.GamePassId)
					end)
					if ok then
						if owns then
							cacheFor(userId)[zone.ZoneId] = true
							persist(player, zone.ZoneId)
						end
						break
					end
					if attempt == LOAD_ATTEMPTS then
						warn(
							`[AutoClickZonePlayerData] не удалось узнать владение зоной {zone.ZoneId} для {player.Name} ({tostring(owns)}) — полагаемся на профиль, окно покупки перепроверит вживую`
						)
					else
						task.wait(LOAD_RETRY_DELAY * attempt)
					end
				end
				pending -= 1
			end)
		end

		while pending > 0 and player.Parent do
			task.wait(0.05)
		end

		loading[userId] = nil
		if player.Parent then
			loaded[userId] = true
		end
	end)
end

function AutoClickZonePlayerData:ClearPlayer(player: Player)
	ownedCache[player.UserId] = nil
	loaded[player.UserId] = nil
	loading[player.UserId] = nil
end

function AutoClickZonePlayerData.Start() end

function AutoClickZonePlayerData.Init()
	ProfileService = Knit.GetService("ProfileService")
end

return AutoClickZonePlayerData
