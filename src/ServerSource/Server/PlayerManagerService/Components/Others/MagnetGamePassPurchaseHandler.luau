local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)

--[[
	MagnetGamePassPurchaseHandler — покупка донат-мечей (Wraithflame, Warring
	Wingblade — MagnetData[key].GamePassId) через Game Pass, по той же схеме,
	что и AutoClickZonePurchaseHandler: владение подтверждает сам Roblox
	(PromptGamePassPurchaseFinished), не ProcessReceipt/чеки.

	В отличие от AutoClickZone, владение мечом хранится в профиле (OwnedMagnets) —
	это уже единственный источник правды для всей механики мечей (клик-сила,
	экипировка, см. MagnetShopHandler), донат-мечи в неё просто добавляются.
	UserOwnsGamePassAsync используется только для восстановления при входе —
	на случай покупки пасса вне сессии (страница игры и т.п.), до того как
	OwnedMagnets успел это подхватить.

	Покупка сразу авто-экипирует — как и покупка обычного меча за Money.
]]
local MagnetGamePassPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

-- gamePassId -> внутренний ключ меча (MagnetData[key].GamePassId). Источник —
-- MagnetData.GamePassMagnets, а НЕ MagnetData.Order (эти мечи туда намеренно
-- не входят — у них своя карточка в ShopPanel, не в панели Cutters).
local function gamePassMagnets(): { [number]: string }
	local map = {}
	for _, name in ipairs(MagnetData.GamePassMagnets) do
		local cfg = MagnetData[name]
		if cfg.GamePassId then
			map[cfg.GamePassId] = name
		end
	end
	return map
end

local byPassId = gamePassMagnets()

local function grantMagnet(player: Player, magnetName: string)
	PlayerManagerService:SetMagnetOwned(player, magnetName)
	PlayerManagerService:EquipMagnet(player, magnetName)
end

-- Клиент шлёт ТОЛЬКО имя меча — сервер сам находит его GamePassId в MagnetData.
function MagnetGamePassPurchaseHandler:PromptPurchase(player: Player, magnetName: string)
	local cfg = magnetName and MagnetData[magnetName]
	if not cfg or not cfg.GamePassId then
		warn(`[MagnetGamePassPurchase] "{tostring(magnetName)}" не продаётся за Game Pass (нет GamePassId)`)
		return
	end

	if PlayerManagerService.Components.MagnetShopHandler:Owns(player, magnetName) then
		return
	end

	MarketplaceService:PromptGamePassPurchase(player, cfg.GamePassId)
end

-- Восстановление владения при входе: для каждого GamePassId-меча, которого ещё
-- нет в OwnedMagnets, живой запрос к Roblox — без похода в тик-цикл, разово на игрока.
local function restoreForPlayer(player: Player)
	local owned = PlayerManagerService:GetPlayerOwnedMagnets(player)

	for gamePassId, magnetName in pairs(byPassId) do
		if not owned[magnetName] then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
				end)

				if ok and owns then
					PlayerManagerService:SetMagnetOwned(player, magnetName)
					if RunService:IsStudio() then
						print(`[MagnetGamePassPurchase] {player.Name} уже владеет "{magnetName}" (восстановлено при входе)`)
					end
				elseif not ok then
					warn(`[MagnetGamePassPurchase] UserOwnsGamePassAsync упал для {player.Name}, gamePassId={gamePassId}:`, owns)
				end
			end)
		end
	end
end

function MagnetGamePassPurchaseHandler.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if RunService:IsStudio() then
			print(
				`[MagnetGamePassPurchase][trace] PromptGamePassPurchaseFinished: player={player and player.Name} gamePassId={gamePassId} wasPurchased={wasPurchased}`
			)
		end

		if not wasPurchased then
			return
		end

		local magnetName = byPassId[gamePassId]
		if not magnetName then
			return -- не наш gamePassId
		end

		grantMagnet(player, magnetName)

		if RunService:IsStudio() then
			print(`[MagnetGamePassPurchase] {player.Name} получил меч "{magnetName}" (Game Pass {gamePassId})`)
		end
	end)

	-- Уже подключённые игроки (Play Solo в Studio — сервер стартует, когда
	-- игрок уже "в игре").
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(restoreForPlayer, player)
	end
end

function MagnetGamePassPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerAdded:Connect(restoreForPlayer)
end

return MagnetGamePassPurchaseHandler
