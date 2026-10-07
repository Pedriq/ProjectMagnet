local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local vide = require(ReplicatedStorage.Packages.Vide)
local Knit = require(ReplicatedStorage.Packages.Knit)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local AudioSettings = require(ReplicatedStorage.ClientSource.audioSettings)
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
Data.upgradeLevels = source({}) -- map[statKey] = number: уровни прокачиваемых статов (Range/Capacity/Mobility)
Data.items = source({}) -- сохранённые предметы (склад): map[id] = itemData
Data.ores = source({}) -- сохранённая руда (profile.Ores): map[oreId] = вес
Data.pressOres = source({}) -- руда в прессе (profile.Press.Ores): map[oreId] = вес — окно Press Queue
Data.world = source(1) -- самый дальний открытый мир (profile.Stats.World): размер Magnetism-паков, см. PowerPackConfig
Data.pressMergeLevel = source(1) -- прокачка Ore Merge (profile.Press.MergeLevel), см. PressMergeConfig
Data.pressHighestOre = source(1) -- высший достигнутый тир руды (profile.Press.HighestOre), индекс OreConfig.Order
Data.mergeEvent = source(nil :: any) -- последний merge { Id, Steps } (PressService.OreMerged): эффекты строк Press Queue
Data.autoCollectPass = source(false) -- куплен Game Pass «OP Auto Collect» (profile.AutoCollectPass): кнопка в HUD скрыта навсегда
Data.ownedZones = source({}) -- map[ZoneId] = true: купленные донатные автоклик-зоны (profile.AutoClickZones) — ОДНО состояние и для Shop, и для касания зоны
Data.zoneCatalog = source({}) -- список зон для Shop (от меньшего множителя к большему), см. AutoClickZoneService:GetZoneCatalog
Data.pressSpeedLevel = source(1) -- уровень скорости пресса (profile.Press.CraftSpeed), см. PressConfig
Data.cashMultiplier = source("1") -- множитель денег (за ребёрсы), EtNum-строка/число
Data.magnet = source({ Name = "FridgeMagnet", Magnetism = 5 }) -- текущий меч { Name, Magnetism }
Data.ownedMagnets = source({}) -- купленные мечи: map[magnetName] = true
Data.tutorialCompleted = source(false) -- обучение пройдено (profile.Tutorial.Completed), см. UI/tutorial
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

local UPGRADE_STATS = { "Range", "Capacity", "Mobility" }

-- === полные множители (для ПРЕВЬЮ на клиенте — попап прироста силы при клике/
-- ударе/автозоне, цены в панели Sell) === Сервер — источник правды (см.
-- PlayerManagerService:GetPlayerCashMultiplier/GetPlayerMagnetismMultiplier),
-- тут то же правило: ТОЧНЫЕ значения множителей складываются — ребёрс (x2) +
-- активный временный бафф (x2) + постоянный донат (x2) = x6; нет баффа/покупки —
-- слагаемое 0.
local function activeBuffMultiplier(buffType: string): number
	local buff = Data.buffs()[buffType]
	if not buff then
		return 0
	end
	if buff.ExpiresAt <= Workspace:GetServerTimeNow() then
		return 0
	end
	return (buff.Bonus or 0) + 1 -- хранится Bonus = Multiplier - 1
end

local function permanentMultiplier(buffType: string): number
	return Data.permanentMultipliers()[buffType] or 0
end

-- Множитель силы за клик/удар/автозону: тот же rebirth-множитель, что считает
-- RebirthHandler (1 + rebirths * MagnetismMultiplierPerRebirth), + баффы.
function Data.fullMagnetismMultiplier(): number
	local base = 1 + Data.rebirths() * RebirthConfig.MagnetismMultiplierPerRebirth
	return base + activeBuffMultiplier("Magnetism") + permanentMultiplier("Magnetism")
end

-- Множитель денег: base читаем из профиля напрямую (Multipliers.Cash, его
-- меняет только RebirthHandler), + баффы.
function Data.fullCashMultiplier(): number
	local base = tonumber(Data.cashMultiplier()) or 1
	return base + activeBuffMultiplier("Money") + permanentMultiplier("Money")
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
	if stats.World ~= nil then
		Data.world(tonumber(stats.World) or 1)
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
	local AutoClickZone = Knit.GetService("AutoClickZoneService")

	--== автоклик-зоны: каталог для Shop + мгновенное «Owned» ==
	-- Покупка (касанием ИЛИ из Shop) сервер подтверждает сигналом — кнопка в Shop меняется
	-- сразу, не дожидаясь точечного обновления профиля (оба пути пишут одно состояние).
	AutoClickZone.ZonePurchased:Connect(function(zoneId)
		local t = table.clone(Data.ownedZones())
		t[zoneId] = true
		Data.ownedZones(t)
	end)
	task.spawn(function()
		for attempt = 1, 6 do
			local ok, list = AutoClickZone:GetZoneCatalog():await()
			if ok and type(list) == "table" and #list > 0 then
				Data.zoneCatalog(list)
				return
			end
			task.wait(2 * attempt)
		end
	end)

	--== Ore Merge: сервер подтвердил объединение -> звук + событие для строк Press Queue ==
	local mergeId = 0
	Knit.GetService("PressService").OreMerged:Connect(function(steps)
		mergeId += 1
		Data.mergeEvent({ Id = mergeId, Steps = steps })
		sfx.play("LevelUP", { pitch = 1.35, volume = 0.7 })
		sfx.play("Buy", { pitch = 1.1 })
	end)

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
		Data.pressOres(savedOres(profile.Press and profile.Press.Ores))
		Data.pressSpeedLevel(tonumber(profile.Press and profile.Press.CraftSpeed) or 1)
		Data.pressMergeLevel(tonumber(profile.Press and profile.Press.MergeLevel) or 1)
		Data.pressHighestOre(tonumber(profile.Press and profile.Press.HighestOre) or 1)
		Data.lockedItems(profile.LockedItems or {})
		Data.ownedZones(table.clone(profile.AutoClickZones or {}))
		Data.autoCollectPass(profile.AutoCollectPass == true)
		Data.tutorialCompleted(type(profile.Tutorial) == "table" and profile.Tutorial.Completed == true)
		-- сохранённая громкость (окно Settings) применяется сразу, до открытия окна
		local settings = if type(profile.Settings) == "table" then profile.Settings else {}
		AudioSettings.load(tonumber(settings.MusicVolume) or 1, tonumber(settings.SfxVolume) or 1)
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
		elseif path[1] == "AutoCollectPass" and path[2] == nil then
			Data.autoCollectPass(a == true)
		elseif path[1] == "Tutorial" and path[2] == "Completed" then
			Data.tutorialCompleted(a == true)
		elseif path[1] == "AutoClickZones" and path[2] ~= nil then
			local t = table.clone(Data.ownedZones())
			t[path[2]] = if a == true then true else nil
			Data.ownedZones(t)
		elseif path[1] == "LockedItems" and path[2] ~= nil then
			local t = table.clone(Data.lockedItems())
			t[path[2]] = a
			Data.lockedItems(t)
		elseif path[1] == "Press" and path[2] == "MergeLevel" then
			Data.pressMergeLevel(tonumber(a) or 1)
		elseif path[1] == "Press" and path[2] == "HighestOre" then
			Data.pressHighestOre(tonumber(a) or 1)
		elseif path[1] == "Press" and path[2] == "CraftSpeed" then
			Data.pressSpeedLevel(tonumber(a) or 1)
		elseif path[1] == "Press" and path[2] == "Ores" and path[3] == nil then
			-- вся таблица руды пресса разом (Ore Merge)
			Data.pressOres(savedOres(a))
		elseif path[1] == "Press" and path[2] == "Ores" and path[3] ~= nil then
			local t = table.clone(Data.pressOres())
			t[path[3]] = if type(a) == "number" and a > 0 then a else nil
			Data.pressOres(t)
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
