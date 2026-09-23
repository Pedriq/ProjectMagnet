local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)

--[[
	WeaponGamePassPurchaseHandler — покупка донат-мечей (Wraithflame, Warring
	Wingblade — WeaponData[key].GamePassId) через Game Pass, по той же схеме,
	что и AutoClickZonePurchaseHandler: владение подтверждает сам Roblox
	(PromptGamePassPurchaseFinished), не ProcessReceipt/чеки.

	В отличие от AutoClickZone, владение мечом хранится в профиле (OwnedWeapons) —
	это уже единственный источник правды для всей механики мечей (клик-сила,
	экипировка, см. WeaponShopHandler), донат-мечи в неё просто добавляются.
	UserOwnsGamePassAsync используется только для восстановления при входе —
	на случай покупки пасса вне сессии (страница игры и т.п.), до того как
	OwnedWeapons успел это подхватить.

	Покупка сразу авто-экипирует — как и покупка обычного меча за Money.
]]
local WeaponGamePassPurchaseHandler = {}

---- Knit Services
local PlayerManagerService

-- gamePassId -> внутренний ключ меча (WeaponData[key].GamePassId). Источник —
-- WeaponData.GamePassWeapons, а НЕ WeaponData.Order (эти мечи туда намеренно
-- не входят — у них своя карточка в ShopPanel, не в панели Cutters).
local function gamePassWeapons(): { [number]: string }
	local map = {}
	for _, name in ipairs(WeaponData.GamePassWeapons) do
		local cfg = WeaponData[name]
		if cfg.GamePassId then
			map[cfg.GamePassId] = name
		end
	end
	return map
end

local byPassId = gamePassWeapons()

local function grantWeapon(player: Player, weaponName: string)
	PlayerManagerService:SetWeaponOwned(player, weaponName)
	PlayerManagerService:EquipWeapon(player, weaponName)
end

-- Клиент шлёт ТОЛЬКО имя меча — сервер сам находит его GamePassId в WeaponData.
function WeaponGamePassPurchaseHandler:PromptPurchase(player: Player, weaponName: string)
	local cfg = weaponName and WeaponData[weaponName]
	if not cfg or not cfg.GamePassId then
		warn(`[WeaponGamePassPurchase] "{tostring(weaponName)}" не продаётся за Game Pass (нет GamePassId)`)
		return
	end

	if PlayerManagerService.Components.WeaponShopHandler:Owns(player, weaponName) then
		return
	end

	MarketplaceService:PromptGamePassPurchase(player, cfg.GamePassId)
end

-- Восстановление владения при входе: для каждого GamePassId-меча, которого ещё
-- нет в OwnedWeapons, живой запрос к Roblox — без похода в тик-цикл, разово на игрока.
local function restoreForPlayer(player: Player)
	local owned = PlayerManagerService:GetPlayerOwnedWeapons(player)

	for gamePassId, weaponName in pairs(byPassId) do
		if not owned[weaponName] then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
				end)

				if ok and owns then
					PlayerManagerService:SetWeaponOwned(player, weaponName)
					if RunService:IsStudio() then
						print(`[WeaponGamePassPurchase] {player.Name} уже владеет "{weaponName}" (восстановлено при входе)`)
					end
				elseif not ok then
					warn(`[WeaponGamePassPurchase] UserOwnsGamePassAsync упал для {player.Name}, gamePassId={gamePassId}:`, owns)
				end
			end)
		end
	end
end

function WeaponGamePassPurchaseHandler.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if RunService:IsStudio() then
			print(
				`[WeaponGamePassPurchase][trace] PromptGamePassPurchaseFinished: player={player and player.Name} gamePassId={gamePassId} wasPurchased={wasPurchased}`
			)
		end

		if not wasPurchased then
			return
		end

		local weaponName = byPassId[gamePassId]
		if not weaponName then
			return -- не наш gamePassId
		end

		grantWeapon(player, weaponName)

		if RunService:IsStudio() then
			print(`[WeaponGamePassPurchase] {player.Name} получил меч "{weaponName}" (Game Pass {gamePassId})`)
		end
	end)

	-- Уже подключённые игроки (Play Solo в Studio — сервер стартует, когда
	-- игрок уже "в игре").
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(restoreForPlayer, player)
	end
end

function WeaponGamePassPurchaseHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerAdded:Connect(restoreForPlayer)
end

return WeaponGamePassPurchaseHandler
