local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoClickZonePlayerData = require(script.Parent.AutoClickZonePlayerData)

--[[
	AutoClickZonePurchaseHandler — "Purchase Manager" из README.md: покупка
	донатных автоклик-зон, через ОБА способа (касание зоны и панель Shop), с
	ОДНИМ и тем же ZoneId в основе.

	Монетизация — Game Pass (README, "Если используются Game Passes, учитывай
	соответствующую модель владения Roblox"): владение проверяется напрямую у
	Roblox (см. AutoClickZonePlayerData), нет ни ProcessReceipt, ни "чек может
	не долететь/прийти с задержкой" — сам Roblox — источник правды.

	ZoneId (Attribute "ZoneId" на модели зоны в Workspace.AutoClickZones) —
	единственный ключ владения. gamePassId — способ оплаты для конкретного
	ZoneId, задаётся отдельным Attribute "gamePassId" на той же модели. Оба
	Attribute'а не хардкодятся в коде (задаются дизайнером зоны прямо в Studio).
]]
local AutoClickZonePurchaseHandler = {}

---- Knit Services
local AutoClickZoneService

-- Иконка по умолчанию для карточки в Shop, если на модели зоны не задан
-- Attribute "icon" — переиспользуем существующий boost-ассет "Strength".
local DEFAULT_ICON = "82923936325309"

-- GetProductInfo — сетевой вызов; кэшируем на весь ран сервера (цена/название
-- Game Pass'а в рантайме не меняются).
local passInfoCache: { [number]: { Name: string, PriceInRobux: number } } = {}

local function getGamePassInfo(gamePassId: number)
	local cached = passInfoCache[gamePassId]
	if cached then
		return cached
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
	end)

	if not ok or not info then
		warn(`[AutoClickZonePurchase] не удалось получить информацию о Game Pass {gamePassId}:`, info)
		return nil
	end

	local entry = { Name = info.Name, PriceInRobux = info.PriceInRobux or 0 }
	passInfoCache[gamePassId] = entry
	return entry
end

local function zonesRoot(): Instance?
	return workspace:FindFirstChild("AutoClickZones")
end

-- tonumber(...) — Attribute "gamePassId" мог быть по ошибке заведён в Studio
-- как String, а не Number/Int64 (Attributes-панель по умолчанию не всегда
-- переключена на нужный тип). "123" == 123 в Lua — это false (разные типы
-- никогда не равны), хотя оба печатаются одинаково — приводим к числу везде,
-- чтобы сравнение работало независимо от того, как задан Attribute в Studio.
local function getGamePassId(zoneModel: Instance): number?
	return tonumber(zoneModel:GetAttribute("gamePassId"))
end

-- Модель зоны по её ZoneId (Attribute) — единственному ключу владения.
local function findZoneModelByZoneId(zoneId: string): Instance?
	local root = zonesRoot()
	if not root then
		return nil
	end

	for _, zoneModel in ipairs(root:GetChildren()) do
		if zoneModel:GetAttribute("ZoneId") == zoneId then
			return zoneModel
		end
	end

	return nil
end

-- Модель зоны по gamePassId — используется, только чтобы сопоставить
-- PromptGamePassPurchaseFinished с ZoneId, см. Start().
local function findZoneModelByGamePassId(gamePassId: number): Instance?
	local root = zonesRoot()
	if not root then
		return nil
	end

	for _, zoneModel in ipairs(root:GetChildren()) do
		if getGamePassId(zoneModel) == gamePassId then
			return zoneModel
		end
	end

	return nil
end

-- Все донат-зоны (заданы И ZoneId, И gamePassId) прямо сейчас в Workspace.
local function collectDonateZones(): { { ZoneId: string, GamePassId: number } }
	local root = zonesRoot()
	if not root then
		return {}
	end

	local result = {}
	for _, zoneModel in ipairs(root:GetChildren()) do
		local zoneId = zoneModel:GetAttribute("ZoneId")
		local gamePassId = getGamePassId(zoneModel)
		if zoneId and gamePassId and gamePassId ~= 0 then
			table.insert(result, { ZoneId = zoneId, GamePassId = gamePassId })
		end
	end
	return result
end

function AutoClickZonePurchaseHandler:IsOwned(player: Player, zoneId: string): boolean
	return AutoClickZonePlayerData:IsOwned(player, zoneId)
end

-- Загрузилось ли владение игрока (профиль + Roblox). Пока нет — решений по зонам не
-- принимаем (см. AutoClickZonePlayerData).
function AutoClickZonePurchaseHandler:IsLoaded(player: Player): boolean
	return AutoClickZonePlayerData:IsLoaded(player)
end

-- Окно покупки уже открыто у игрока: [userId] = { gamePassId, at }. Касание зоны и кнопка
-- в Shop идут через ОДНУ функцию openPrompt, поэтому одновременно два окна на один пасс
-- не откроются (иначе можно было бы нажать «купить» дважды). Запись снимается, когда
-- Roblox сообщит о закрытии окна (PromptGamePassPurchaseFinished) — или по таймауту.
local PROMPT_TIMEOUT = 60
local openPrompts: { [number]: { gamePassId: number, at: number } } = {}

local function openPrompt(player: Player, gamePassId: number)
	local open = openPrompts[player.UserId]
	if open and open.gamePassId == gamePassId and os.clock() - open.at < PROMPT_TIMEOUT then
		return
	end
	openPrompts[player.UserId] = { gamePassId = gamePassId, at = os.clock() }
	MarketplaceService:PromptGamePassPurchase(player, gamePassId)
end

-- Единая точка запроса покупки для ОБОИХ путей (касание — AutoClickZoneHandler,
-- магазин — PromptValidatedPurchase ниже): если зона уже куплена (по кэшу —
-- быстро, без yield), окно покупки не открывается вообще.
function AutoClickZonePurchaseHandler:RequestPurchase(player: Player, zoneId: string, gamePassId: number)
	if AutoClickZonePlayerData:IsOwned(player, zoneId) then
		return
	end

	-- Живая перепроверка у Roblox (yield) перед окном — в отдельном потоке, чтобы не
	-- тормозить тик Zone Manager. Кэш мог отстать (пасс куплен на другом сервере/вне игры).
	task.spawn(function()
		if AutoClickZonePlayerData:Refresh(player, zoneId, gamePassId) then
			return
		end
		if not player.Parent then
			return
		end


		-- владение могло появиться, пока шёл запрос
		if AutoClickZonePlayerData:IsOwned(player, zoneId) then
			return
		end
		openPrompt(player, gamePassId)
	end)
end

-- Покупка С КЛИЕНТА (панель Shop): клиент присылает ТОЛЬКО ZoneId — сервер
-- сам находит модель зоны и её gamePassId. Тут (в отличие от касания) делаем
-- ЖИВУЮ проверку через Roblox (Refresh), а не кэш — это разовое действие по
-- клику, а не горячий тик, так что yield безопасен и подстраховывает от
-- рассинхрона кэша (например, пасс куплен вне игры).
function AutoClickZonePurchaseHandler:PromptValidatedPurchase(player: Player, zoneId: string)
	local zoneModel = findZoneModelByZoneId(zoneId)
	if not zoneModel then
		warn(`[AutoClickZonePurchase] клиент запросил покупку неизвестного ZoneId: {tostring(zoneId)}`)
		return
	end

	local gamePassId = getGamePassId(zoneModel)
	if not gamePassId or gamePassId == 0 then
		warn(`[AutoClickZonePurchase] у зоны "{zoneModel:GetFullName()}" (ZoneId={zoneId}) не задан gamePassId`)
		return
	end

	-- Кэш/профиль — общее состояние с касанием зоны; живая проверка Roblox — подстраховка.
	local owned = AutoClickZonePlayerData:IsOwned(player, zoneId)
		or AutoClickZonePlayerData:Refresh(player, zoneId, gamePassId)

	if owned then
		-- повторно не списываем: окно покупки не открывается вообще
		AutoClickZoneService.Client.ShowMessage:Fire(player, "Already Owned")
		return
	end

	openPrompt(player, gamePassId)
end

-- Каталог зон для панели Shop: по одной карточке на ZoneId, Title/Price — из
-- самого Game Pass'а (GetProductInfo), а не хардкодятся в коде.
function AutoClickZonePurchaseHandler:GetCatalog(player: Player): { any }
	-- Purchased берётся из кэша владения — дождёмся его загрузки, иначе у уже купленных
	-- зон будет Purchased = false в зависимости от скорости входа.
	AutoClickZonePlayerData:WaitUntilLoaded(player, 10)

	local root = zonesRoot()
	if not root then
		return {}
	end

	local seen: { [string]: boolean } = {}
	local catalog = {}

	for _, zoneModel in ipairs(root:GetChildren()) do
		local zoneId = zoneModel:GetAttribute("ZoneId")
		local gamePassId = getGamePassId(zoneModel)

		if zoneId and gamePassId and gamePassId ~= 0 and not seen[zoneId] then
			seen[zoneId] = true

			local info = getGamePassInfo(gamePassId)
			if info then
				table.insert(catalog, {
					ZoneId = zoneId,
					Title = info.Name,
					Price = info.PriceInRobux,
					Multiplier = tonumber(zoneModel:GetAttribute("multiplier")) or 1,
					Icon = zoneModel:GetAttribute("icon") or DEFAULT_ICON,
					Purchased = AutoClickZonePlayerData:IsOwned(player, zoneId),
				})
			end
		end
	end

	-- От меньшего множителя к большему (x10 -> x25 -> x100 ...); при равенстве — по цене.
	table.sort(catalog, function(a, b)
		if a.Multiplier ~= b.Multiplier then
			return a.Multiplier < b.Multiplier
		end
		return a.Price < b.Price
	end)

	-- Tier = позиция в отсортированном списке — карточки идут от слабой к сильной, и это
	-- же задаёт цвет/эффект карточки (UI.components.ZoneCard).
	-- Раньше Tier читался из Attribute "tier" на модели зоны, но он нигде не был
	-- выставлен (всегда nil -> все карточки выглядели одинаково).
	for index, entry in ipairs(catalog) do
		entry.Tier = index
	end

	return catalog
end

-- Диагностика конфигурации зон — при старте, в Output.
local function warnAboutMisconfiguredZones()
	local root = zonesRoot()
	if not root then
		return
	end

	local seenZoneIds: { [string]: Instance } = {}

	for _, zoneModel in ipairs(root:GetChildren()) do
		local zoneId = zoneModel:GetAttribute("ZoneId")
		local rawGamePassId = zoneModel:GetAttribute("gamePassId")
		local gamePassId = getGamePassId(zoneModel)

		if rawGamePassId ~= nil and typeof(rawGamePassId) ~= "number" then
			warn(
				`[AutoClickZonePurchase] у "{zoneModel:GetFullName()}" Attribute "gamePassId" имеет тип {typeof(rawGamePassId)}, а не Number/Int64 (значение "{rawGamePassId}") — сравнение с реальным Game Pass id работает только благодаря tonumber()-коэрсии в коде, лучше поправить тип в Attributes-панели Studio.`
			)
		end

		if gamePassId and gamePassId ~= 0 then
			if not zoneId or zoneId == "" then
				warn(
					`[AutoClickZonePurchase] у донат-зоны "{zoneModel:GetFullName()}" задан gamePassId, но НЕ задан Attribute "ZoneId" — владение для неё нельзя отследить (см. README.md), зона будет недоступна для покупки.`
				)
				continue
			end

			if seenZoneIds[zoneId] then
				warn(
					`[AutoClickZonePurchase] ZoneId "{zoneId}" повторяется у "{zoneModel:GetFullName()}" и "{seenZoneIds[zoneId]:GetFullName()}" — ZoneId должен быть уникален для каждой зоны.`
				)
			end
			seenZoneIds[zoneId] = zoneModel
		end
	end
end

function AutoClickZonePurchaseHandler.Start()
	-- PromptGamePassPurchaseFinished — сигнал (не свойство, как ProcessReceipt
	-- у Developer Product): несколько :Connect() спокойно сосуществуют, не
	-- нужен общий роутер вроде MarketplaceReceiptRouter.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		-- окно закрылось (купили или отменили) — можно открывать новое
		if player and openPrompts[player.UserId] and openPrompts[player.UserId].gamePassId == gamePassId then
			openPrompts[player.UserId] = nil
		end

		-- БЕЗУСЛОВНЫЙ трейс — печатается для КАЖДОГО срабатывания события, даже
		-- если это не наш gamePassId или покупку отменили. Если этой строки нет
		-- в Output вообще после покупки — событие в принципе не долетает
		-- (среда/тест), дело не в нашей логике сопоставления зоны.

		if not wasPurchased then
			return
		end

		local zoneModel = findZoneModelByGamePassId(gamePassId)
		if not zoneModel then
			return -- не наш gamePassId
		end

		local zoneId = zoneModel:GetAttribute("ZoneId")
		if not zoneId or zoneId == "" then
			warn(
				`[AutoClickZonePurchase] покупка Game Pass {gamePassId} сопоставлена с зоной "{zoneModel:GetFullName()}" без ZoneId — не могу сохранить покупку`
			)
			return
		end

		AutoClickZonePlayerData:MarkOwned(player, zoneId)
		AutoClickZoneService.Client.ZonePurchased:Fire(player, zoneId)

	end)

	-- Уже подключённые игроки (например, Play Solo в Studio, где сервер
	-- стартует, когда игрок уже "в игре") — LoadForPlayer сам параллелен по
	-- зонам, ждать все зоны последовательно не нужно.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			AutoClickZonePlayerData:LoadForPlayer(player, collectDonateZones())
		end)
	end

	task.delay(3, warnAboutMisconfiguredZones)
end

function AutoClickZonePurchaseHandler.Init()
	AutoClickZoneService = Knit.GetService("AutoClickZoneService")

	Players.PlayerAdded:Connect(function(player)
		AutoClickZonePlayerData:LoadForPlayer(player, collectDonateZones())
	end)

	Players.PlayerRemoving:Connect(function(player)
		openPrompts[player.UserId] = nil
		AutoClickZonePlayerData:ClearPlayer(player)
	end)
end

return AutoClickZonePurchaseHandler
