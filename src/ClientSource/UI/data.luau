local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local vide = require(ReplicatedStorage.Packages.Vide)
local Knit = require(ReplicatedStorage.Packages.Knit)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)

local source = vide.source

--[[
	Data — реактивное зеркало данных игрока для UI.

	Все поля — Vide-источники: читай как геттеры (Data.money()), а в свойствах
	Vide просто передавай сам источник (Text = Data.money -> обновляется сам).

	Заполняется из:
	  ProfileService.GetData            — полный снапшот при старте
	  ProfileService.UpdateSpecificData — точечные изменения (сила, деньги, уровень…)
	  PlayerManagerService.CarryInventoryChanged — инвентарь для переноса

	Инициализация: Data.start() из InitPlayerUI ПОСЛЕ Knit.OnStart().
]]
local Data = {}

Data.magnetism = source("0") -- EtNum-строка
Data.money = source("0") -- EtNum-строка
Data.rebirths = source(0)
Data.level = source(1)
Data.carryCount = source(0) -- суммарный вес руды, которую игрок несёт (ещё не сохранена)
Data.carryCapacity = source(1) -- вместимость переноски, в единицах веса
Data.upgradeLevels = source({}) -- map[statKey] = number: уровни прокачиваемых статов (Range/Agility/Capacity/Mobility)
Data.items = source({}) -- сохранённые предметы (склад): map[id] = itemData
Data.ores = source({}) -- сохранённая руда (profile.Ores): map[oreId] = вес
Data.cashMultiplier = source("1") -- множитель денег (за ребёрсы), EtNum-строка/число
Data.magnet = source({ Name = "Stick", Magnetism = 5 }) -- текущий меч { Name, Magnetism }
Data.ownedMagnets = source({}) -- купленные мечи: map[magnetName] = true
Data.ready = source(false) -- пришёл ли первый снапшот профиля
Data.friendBonusPercent = source(0) -- бонус к силе за клик от друзей в сессии, в процентах
Data.buffs = source({}) -- активные временные баффы: map[buffType] = { ExpiresAt: number, Bonus: number }
Data.permanentMultipliers = source({ Magnetism = 0, Money = 0 }) -- постоянные донат-множители (HUD -> BuffBuyButton): 0 = не куплен, иначе текущая купленная ступень
Data.lockedItems = source({}) -- заблокированные от продажи имена предметов (панель Sell Loot, кнопка Lock): map[itemName] = true.

-- Только числовые записи руда = вес: в старых профилях под Ores могут лежать
-- чужие поля (TotalWeight/Items из первого прототипа).
local function savedOres(ores: any): { [string]: number }
	local result = {}
	if type(ores) == "table" then
		for oreId, weight in pairs(ores) do
			if type(weight) == "number" then
				result[oreId] = weight
			end
		end
	end
	return result
end

local started = false

local UPGRADE_STATS = { "Range", "Agility", "Capacity", "Mobility" }

-- === полные множители (для ПРЕВЬЮ на клиенте — попап прироста силы при клике/
-- ударе/автозоне, цены в панели Sell) === Сервер — источник правды (см.
-- PlayerManagerService:GetPlayerCashMultiplier/GetPlayerMagnetismMultiplier),
-- тут та же формула: base (ребёрс) + бонус активного временного баффа + бонус
-- постоянного донат-множителя. Раньше превью считало только ребёрс-множитель,
-- игнорируя баффы и донат-множитель — показывало заниженное число.
local function activeBuffBonus(buffType: string): number
	local buff = Data.buffs()[buffType]
	if not buff then
		return 0
	end
	if buff.ExpiresAt <= Workspace:GetServerTimeNow() then
		return 0
	end
	return buff.Bonus or 0
end

local function permanentBonus(buffType: string): number
	local owned = Data.permanentMultipliers()[buffType] or 0
	return owned > 0 and (owned - 1) or 0
end

-- Множитель силы за клик/удар/автозону: тот же rebirth-множитель, что считает
-- RebirthHandler (1 + rebirths * MagnetismMultiplierPerRebirth), + баффы.
function Data.fullMagnetismMultiplier(): number
	local base = 1 + Data.rebirths() * RebirthConfig.MagnetismMultiplierPerRebirth
	return base + activeBuffBonus("Magnetism") + permanentBonus("Magnetism")
end

-- Множитель денег: base читаем из профиля напрямую (Multipliers.Cash, его
-- меняет только RebirthHandler), + баффы.
function Data.fullCashMultiplier(): number
	local base = tonumber(Data.cashMultiplier()) or 1
	return base + activeBuffBonus("Money") + permanentBonus("Money")
end

local function applyStats(stats: { [string]: any })
	if stats.Magnetism ~= nil then
		Data.magnetism(stats.Magnetism)
	end
	if stats.Money ~= nil then
		Data.money(stats.Money)
	end
	if stats.Rebirth ~= nil then
		Data.rebirths(stats.Rebirth)
	end
	if stats.Level ~= nil then
		Data.level(stats.Level)
	end

	local levels: { [string]: any }? = nil
	for _, key in ipairs(UPGRADE_STATS) do
		if stats[key] ~= nil then
			levels = levels or table.clone(Data.upgradeLevels())
			levels[key] = stats[key]
		end
	end
	if levels then
		Data.upgradeLevels(levels)
	end
end

function Data.start()
	if started then
		return
	end
	started = true

	local Profile = Knit.GetService("ProfileService")
	local PlayerManager = Knit.GetService("PlayerManagerService")

	--== профиль: полный снапшот ==
	Profile.GetData:Connect(function(profile)
		if type(profile) ~= "table" then
			return
		end
		if profile.Stats then
			applyStats(profile.Stats)
		end
		if profile.Multipliers and profile.Multipliers.Cash ~= nil then
			Data.cashMultiplier(profile.Multipliers.Cash)
		end
		if profile.PermanentMultipliers then
			Data.permanentMultipliers({
				Magnetism = profile.PermanentMultipliers.Magnetism or 0,
				Money = profile.PermanentMultipliers.Money or 0,
			})
		end
		if profile.Magnet then
			Data.magnet(profile.Magnet)
		end
		Data.ownedMagnets(profile.OwnedMagnets or {})
		Data.items(profile.Items or {})
		Data.ores(savedOres(profile.Ores))
		Data.lockedItems(profile.LockedItems or {})
		Data.ready(true)
	end)
	Profile.GetData:Fire()

	--== профиль: точечные обновления ==
	Profile.UpdateSpecificData:Connect(function(path, a, b)
		local key = table.concat(path, "/")
		if key == "Items/Add" then
			local t = table.clone(Data.items())
			t[a] = b
			Data.items(t)
		elseif key == "Items/Remove" then
			local t = table.clone(Data.items())
			t[a] = nil
			Data.items(t)
		elseif key == "Items/Clear" then
			Data.items({})
		elseif path[1] == "Stats" and path[2] ~= nil then
			if path[2] == "Level" and type(a) == "number" and a > Data.level() then
				sfx.play("LevelUP")
			end
			applyStats({ [path[2]] = a })
		elseif path[1] == "Multipliers" and path[2] == "Cash" then
			Data.cashMultiplier(a)
		elseif path[1] == "PermanentMultipliers" and path[2] ~= nil then
			local t = table.clone(Data.permanentMultipliers())
			t[path[2]] = a
			Data.permanentMultipliers(t)
		elseif path[1] == "LockedItems" and path[2] ~= nil then
			local t = table.clone(Data.lockedItems())
			t[path[2]] = a
			Data.lockedItems(t)
		elseif path[1] == "Ores" and path[2] ~= nil then
			local t = table.clone(Data.ores())
			t[path[2]] = if type(a) == "number" then a else nil
			Data.ores(t)
		elseif path[1] == "Magnet" and path[2] == nil then
			Data.magnet(a)
		elseif path[1] == "OwnedMagnets" and path[2] ~= nil then
			local t = table.clone(Data.ownedMagnets())
			t[path[2]] = a
			Data.ownedMagnets(t)
		end
	end)

	--== инвентарь для переноса ==
	PlayerManager.CarryInventoryChanged:Connect(function(count, capacity)
		Data.carryCount(count)
		Data.carryCapacity(capacity)
	end)
	PlayerManager
		:GetCarryInfo()
		:andThen(function(info)
			if type(info) == "table" then
				Data.carryCount(info.Count or 0)
				Data.carryCapacity(info.Capacity or 1)
			end
		end)
		:catch(function() end)

	--== временные баффы (панель Shop -> Boosts, ActiveBuffsBar) ==
	PlayerManager.BuffChanged:Connect(function(buffType, expiresAt, bonus)
		local t = table.clone(Data.buffs())
		t[buffType] = { ExpiresAt = expiresAt, Bonus = bonus }
		Data.buffs(t)
	end)
	-- снапшот при старте: сервер мог восстановить баффы из профиля (релог) ещё
	-- до того, как мы подписались на BuffChanged выше.
	PlayerManager
		:GetActiveBuffs()
		:andThen(function(buffs)
			if type(buffs) == "table" then
				Data.buffs(buffs)
			end
		end)
		:catch(function() end)

	--== бонус за друзей в сессии (кнопка Invite) ==
	PlayerManager.FriendBonusChanged:Connect(function(_count, percent)
		Data.friendBonusPercent(percent)
	end)
	PlayerManager
		:GetFriendBonusInfo()
		:andThen(function(info)
			if type(info) == "table" then
				Data.friendBonusPercent(info.Percent or 0)
			end
		end)
		:catch(function() end)
end

return Data
