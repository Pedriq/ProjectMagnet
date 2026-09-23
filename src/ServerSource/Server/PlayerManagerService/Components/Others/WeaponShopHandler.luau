local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)

--[[
	WeaponShopHandler — покупка мечей за Money и их экипировка. Конфиг — WeaponData.

	Покупка за Money: сервер берёт цену из WeaponData[name].Price (EtNum-строка),
	сверяет с деньгами игрока, списывает, помечает меч купленным (OwnedWeapons) и
	сразу экипирует.

	Экипировка: profile.Weapon = { Name, Strength } (Strength читает ClickHandler
	за каждый клин), затем перевыдаём модель меча и хитбокс. Для Dynamic-мечей
	(Wraithflame, Warring Wingblade — см. WeaponData) Strength не берётся из
	конфига напрямую, а считается заново через WeaponData.effectiveStrength —
	это единственное место, где Dynamic-сила фиксируется в профиль, поэтому она
	актуальна ровно на момент последней экипировки этого меча.

	За Robux (обычные мечи, в обход цены Money) — WeaponData[name].RobuxProductId,
	см. WeaponRobuxPurchaseHandler (дев-продукт, не через этот файл — тот только
	читает Owns/EquipWeapon отсюда). Донат-мечи (GamePassId) покупаются через
	WeaponGamePassPurchaseHandler — тоже не через этот файл.

	Stick (нет поля Price) не продаётся — он всегда в OwnedWeapons из ProfileTemplate.
]]

local WeaponShopHandler = {}

---- Knit Services
local PlayerManagerService

local function weaponConfig(name: string)
	return type(name) == "string" and WeaponData[name] or nil
end

function WeaponShopHandler:Owns(player, name: string): boolean
	local owned = PlayerManagerService:GetPlayerOwnedWeapons(player)
	return owned ~= nil and owned[name] == true
end

-- Поставить меч текущим (должен быть куплен). true — успех.
function WeaponShopHandler:EquipWeapon(player, name: string): boolean
	local cfg = weaponConfig(name)
	if not cfg then
		warn(`[WeaponShop] неизвестный меч "{tostring(name)}"`)
		return false
	end
	if not self:Owns(player, name) then
		return false
	end

	-- profile.Weapon.Name должен быть ВНУТРЕННИМ ключом (как в WeaponData/OwnedWeapons),
	-- а не cfg.Name (это отображаемое имя, "Chef's Favourite" и т.п.) — иначе
	-- CreateWeaponHitbox ищет WeaponData[weaponName] по отображаемому имени и не находит.
	local owned = PlayerManagerService:GetPlayerOwnedWeapons(player)
	PlayerManagerService:ChangeWeapon(player, { Name = name, Strength = WeaponData.effectiveStrength(name, owned) })

	-- перевыдать модель меча в руку и пересобрать хитбокс под новый меч
	PlayerManagerService:GiveWeapon(player)
	PlayerManagerService:CreateWeaponHitbox(player)
	return true
end

-- Покупка меча за Money (и сразу экипировка). Если уже куплен — просто экипирует.
-- true — успех, false — нет денег / не продаётся / нет такого меча.
function WeaponShopHandler:BuyWithMoney(player, name: string): boolean
	local cfg = weaponConfig(name)
	if not cfg then
		warn(`[WeaponShop] неизвестный меч "{tostring(name)}"`)
		return false
	end

	if self:Owns(player, name) then
		return self:EquipWeapon(player, name)
	end

	if not cfg.Price then
		return false -- Stick / меч не продаётся за Money
	end

	local money = PlayerManagerService:GetPlayerMoney(player) or "0"
	if EtNum.me(cfg.Price, money) then -- цена > денег
		return false
	end

	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.sub(money, cfg.Price)))
	PlayerManagerService:SetWeaponOwned(player, name)
	self:EquipWeapon(player, name)
	return true
end

function WeaponShopHandler.Start() end

function WeaponShopHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return WeaponShopHandler
