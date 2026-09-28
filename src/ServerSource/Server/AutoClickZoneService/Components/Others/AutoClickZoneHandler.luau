local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoClickZonePurchaseHandler = require(script.Parent.AutoClickZonePurchaseHandler)

--[[
	AutoClickZoneHandler — "Zone Manager" из README.md: определение зоны,
	проверку владения и запуск автоклика при касании.

	Один тик раз в TICK_INTERVAL на ВСЮ игру (не поток на игрока и не поток на
	зону): раз в 0.5с строим список HumanoidRootPart всех онлайн-игроков и одним
	GetPartsInPart на зону проверяем, кто внутри. Кто вышел из зоны — просто не
	попадает в выдачу на следующем тике, отдельно "останавливать" нечего.

	Структура: Workspace.AutoClickZones — папка с моделями AutoClickZone.
	У каждой модели-зоны — свои Zone/TeslaCoil и свои Attributes
	multiplier/rebirth/gamePassId/ZoneId. См. collectZoneModels.

	Владение донатной зоной проверяется по ZoneId (Attribute на модели), НЕ по
	gamePassId — ZoneId единственный ключ хранения, см. AutoClickZonePlayerData.
	Монетизация — Game Pass (README: "учитывай соответствующую модель владения
	Roblox"), IsOwned читает только локальный кэш (без yield — безопасно для
	тик-цикла ниже), см. AutoClickZonePurchaseHandler/AutoClickZonePlayerData.
]]
local AutoClickZoneHandler = {}

---- Datas
local TICK_INTERVAL = 0.5
local MESSAGE_DEBOUNCE = 3 -- как часто можно повторно показывать "Not Enough Yet" одному игроку
local ZONE_MESSAGE_TEXT = "Not Enough Yet"

---- Knit Services
local PlayerManagerService
local ClickerService
local AutoClickZoneService

---- State
local lastMessageAt: { [number]: number } = {} -- [userId] = os.clock()
local lastPromptedZone: { [number]: string } = {} -- [userId] = GetFullName() донат-зоны, уже предложенной за этот заход

---- Assets
-- "Zone" может быть и сам детект-партом, и папкой с партом внутри — поддерживаем оба варианта.
local function getZonePart(zoneModel: Instance): BasePart?
	local zoneChild = zoneModel:FindFirstChild("Zone")
	if not zoneChild then
		return nil
	end

	if zoneChild:IsA("BasePart") then
		return zoneChild
	end

	return zoneChild:FindFirstChildWhichIsA("BasePart")
end

local function getTeslaCoil(zoneModel: Instance): Instance?
	return zoneModel:FindFirstChild("TeslaCoil")
end

-- Workspace.AutoClickZones — папка с моделями AutoClickZone (у каждой свои
-- Zone/TeslaCoil и свои Attributes multiplier/rebirth/gamePassId).
local function collectZoneModels(root: Instance): { Instance }
	local zones = {}
	for _, child in ipairs(root:GetChildren()) do
		if getZonePart(child) then
			table.insert(zones, child)
		end
	end
	return zones
end

function AutoClickZoneHandler:_HasAccess(player: Player, zoneModel: Instance): boolean
	local zoneId = zoneModel:GetAttribute("ZoneId")
	-- tonumber(...) — Attribute мог быть по ошибке задан как String в Studio,
	-- см. AutoClickZonePurchaseHandler.getGamePassId.
	local gamePassId = tonumber(zoneModel:GetAttribute("gamePassId"))

	if zoneId and gamePassId and gamePassId ~= 0 then
		return AutoClickZonePurchaseHandler:IsOwned(player, zoneId)
	end

	local requiredRebirth = zoneModel:GetAttribute("rebirth") or 0
	local playerRebirths = tonumber(PlayerManagerService:GetPlayerRebirths(player)) or 0

	return playerRebirths >= requiredRebirth
end

function AutoClickZoneHandler:_ShowDeniedMessage(player: Player)
	local now = os.clock()
	local last = lastMessageAt[player.UserId]

	if last and now - last < MESSAGE_DEBOUNCE then
		return
	end

	lastMessageAt[player.UserId] = now
	AutoClickZoneService.Client.ShowMessage:Fire(player, ZONE_MESSAGE_TEXT)
end

function AutoClickZoneHandler:_HandleDenied(player: Player, zoneModel: Instance)
	self:_ShowDeniedMessage(player)

	local zoneId = zoneModel:GetAttribute("ZoneId")
	local gamePassId = tonumber(zoneModel:GetAttribute("gamePassId"))
	local userId = player.UserId

	if not zoneId or not gamePassId or gamePassId == 0 then
		lastPromptedZone[userId] = nil
		return
	end

	-- Game Pass предлагаем один раз за заход в конкретную зону, а не каждый тик.
	local zoneKey = zoneModel:GetFullName()
	if lastPromptedZone[userId] == zoneKey then
		return
	end
	lastPromptedZone[userId] = zoneKey

	if RunService:IsStudio() then
		print(`[AutoClickZoneHandler][trace] _HandleDenied: {player.Name} зона="{zoneKey}" zoneId={zoneId} gamePassId={gamePassId}`)
	end

	-- RequestPurchase сам ещё раз проверит владение по кэшу (README: защита от
	-- гонки между касанием и одновременной покупкой в магазине) — окно покупки
	-- не откроется, если зона уже куплена другим путём между тиками.
	AutoClickZonePurchaseHandler:RequestPurchase(player, zoneId, gamePassId)
end

function AutoClickZoneHandler:_HandleGranted(player: Player, zoneModel: Instance)
	lastPromptedZone[player.UserId] = nil

	local multiplier = zoneModel:GetAttribute("multiplier") or 1

	-- Анимация атаки в этом проекте всегда играется клиентом (см.
	-- RockAttackAnimation) — сервер тут не проигрывает её сам, а полагается на
	-- ZonePulse ниже, который на клиенте (AutoClickZoneController) запускает тот
	-- же свинг, что и обычный удар по камню.
	ClickerService:Click(player, multiplier)

	local teslaCoil = getTeslaCoil(zoneModel)
	if teslaCoil then
		AutoClickZoneService.Client.ZonePulse:Fire(player, teslaCoil)
	end
end

function AutoClickZoneHandler:_Tick()
	local root = workspace:FindFirstChild("AutoClickZones")
	if not root then
		return
	end

	local zones = collectZoneModels(root)
	if #zones == 0 then
		return
	end

	local roots: { BasePart } = {}
	local rootToPlayer: { [BasePart]: Player } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")

		if hrp then
			table.insert(roots, hrp :: BasePart)
			rootToPlayer[hrp :: BasePart] = player
		end
	end

	if #roots == 0 then
		return
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	params.MaxParts = #roots

	local processed: { [Player]: boolean } = {}

	for _, zoneModel in ipairs(zones) do
		local zonePart = getZonePart(zoneModel) :: BasePart

		for _, hitPart in ipairs(workspace:GetPartsInPart(zonePart, params)) do
			local player = rootToPlayer[hitPart]

			if player and not processed[player] then
				processed[player] = true

				local ok, err = pcall(function()
					if self:_HasAccess(player, zoneModel) then
						self:_HandleGranted(player, zoneModel)
					else
						self:_HandleDenied(player, zoneModel)
					end
				end)

				if not ok then
					warn("[AutoClickZoneHandler] ошибка обработки игрока:", err)
				end
			end
		end
	end
end

-- Разовая диагностика при старте сервера — чтобы сразу увидеть в Output,
-- нашлась ли папка/зоны и правильная ли у них структура (Zone + BasePart).
local function logStartupDiagnostics()
	local root = workspace:FindFirstChild("AutoClickZones")
	if not root then
		warn('[AutoClickZoneHandler] Workspace.AutoClickZones не найден — автоклик-зоны не будут работать')
		return
	end

	local zones = collectZoneModels(root)
	print(`[AutoClickZoneHandler] найдено зон с корректной структурой (Zone + Part): {#zones}`)

	for _, child in ipairs(root:GetChildren()) do
		if not getZonePart(child) then
			warn(
				`[AutoClickZoneHandler] у "{child:GetFullName()}" нет Zone/<BasePart> — зона игнорируется`
			)
		elseif not getTeslaCoil(child) then
			warn(`[AutoClickZoneHandler] у "{child:GetFullName()}" нет модели "TeslaCoil" — эффект пульсации не сработает`)
		end

		-- Дамп РЕАЛЬНО прочитанных Attribute'ов каждой зоны — самый быстрый способ
		-- поймать опечатку в имени/регистре Attribute'а (GetAttribute с неверным
		-- именем молча вернёт nil, без ошибки).
		print(
			`[AutoClickZoneHandler] "{child:GetFullName()}": ZoneId={child:GetAttribute("ZoneId")} gamePassId={child:GetAttribute("gamePassId")} rebirth={child:GetAttribute("rebirth")} multiplier={child:GetAttribute("multiplier")}`
		)
	end
end

function AutoClickZoneHandler.Start()
	logStartupDiagnostics()

	while true do
		task.wait(TICK_INTERVAL)

		local ok, err = pcall(function()
			AutoClickZoneHandler:_Tick()
		end)

		if not ok then
			warn("[AutoClickZoneHandler] ошибка тика:", err)
		end
	end
end

function AutoClickZoneHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ClickerService = Knit.GetService("ClickerService")
	AutoClickZoneService = Knit.GetService("AutoClickZoneService")

	Players.PlayerRemoving:Connect(function(player)
		lastMessageAt[player.UserId] = nil
		lastPromptedZone[player.UserId] = nil
	end)
end

return AutoClickZoneHandler
