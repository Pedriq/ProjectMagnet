local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)

--[[
	MagnetShopHandler — покупка мечей за Money и их экипировка. Конфиг — MagnetData.

	Покупка за Money: сервер берёт цену из MagnetData[name].Price (EtNum-строка),
	сверяет с деньгами игрока, списывает, помечает меч купленным (OwnedMagnets) и
	сразу экипирует.

	Экипировка: profile.Magnet = { Name, Magnetism } (Magnetism читает ClickHandler
	за каждый клин), затем перевыдаём модель меча и хитбокс. Для Dynamic-мечей
	(Wraithflame, Warring Wingblade — см. MagnetData) Magnetism не берётся из
	конфига напрямую, а считается заново через MagnetData.effectiveMagnetism —
	это единственное место, где Dynamic-сила фиксируется в профиль, поэтому она
	актуальна ровно на момент последней экипировки этого меча.

	За Robux (обычные мечи, в обход цены Money) — MagnetData[name].RobuxProductId,
	см. MagnetRobuxPurchaseHandler (дев-продукт, не через этот файл — тот только
	читает Owns/EquipMagnet отсюда). Донат-мечи (GamePassId) покупаются через
	MagnetGamePassPurchaseHandler — тоже не через этот файл.

	Stick (нет поля Price) не продаётся — он всегда в OwnedMagnets из ProfileTemplate.
]]

local MagnetShopHandler = {}

---- Knit Services
local PlayerManagerService

local function magnetConfig(name: string)
	return type(name) == "string" and MagnetData[name] or nil
end

function MagnetShopHandler:Owns(player, name: string): boolean
	local owned = PlayerManagerService:GetPlayerOwnedMagnets(player)
	return owned ~= nil and owned[name] == true
end

-- Поставить меч текущим (должен быть куплен). true — успех.
function MagnetShopHandler:EquipMagnet(player, name: string): boolean
	local cfg = magnetConfig(name)
	if not cfg then
		warn(`[MagnetShop] неизвестный меч "{tostring(name)}"`)
		return false
	end
	if not self:Owns(player, name) then
		return false
	end

	-- profile.Magnet.Name должен быть ВНУТРЕННИМ ключом (как в MagnetData/OwnedMagnets),
	-- а не cfg.Name (это отображаемое имя, "Chef's Favourite" и т.п.) — иначе
	-- CreateMagnetHitbox ищет MagnetData[magnetName] по отображаемому имени и не находит.
	local owned = PlayerManagerService:GetPlayerOwnedMagnets(player)
	PlayerManagerService:ChangeMagnet(player, { Name = name, Magnetism = MagnetData.effectiveMagnetism(name, owned) })

	-- перевыдать модель меча в руку и пересобрать хитбокс под новый меч
	PlayerManagerService:GiveMagnet(player)
	PlayerManagerService:CreateMagnetHitbox(player)
	return true
end

-- Покупка меча за Money (и сразу экипировка). Если уже куплен — просто экипирует.
-- true — успех, false — нет денег / не продаётся / нет такого меча.
function MagnetShopHandler:BuyWithMoney(player, name: string): boolean
	local cfg = magnetConfig(name)
	if not cfg then
		warn(`[MagnetShop] неизвестный меч "{tostring(name)}"`)
		return false
	end

	if self:Owns(player, name) then
		return self:EquipMagnet(player, name)
	end

	if not cfg.Price then
		return false -- Stick / меч не продаётся за Money
	end

	local money = PlayerManagerService:GetPlayerMoney(player) or "0"
	if EtNum.me(cfg.Price, money) then -- цена > денег
		return false
	end

	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.sub(money, cfg.Price)))
	PlayerManagerService:SetMagnetOwned(player, name)
	self:EquipMagnet(player, name)
	return true
end

function MagnetShopHandler.Start() end

function MagnetShopHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return MagnetShopHandler
