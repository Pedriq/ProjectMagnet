local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)

--[[
	PressCraftHandler — крафт предметов из руды в прессе и их продажа.

	На каждого игрока свой поток: как только какой-то руды в прессе набралось
	PressConfig.WEIGHT_PER_ITEM, ждём GetCraftInterval(CraftSpeed), списываем
	вес и делаем случайный предмет редкости руды (OreConfig.Rarity -> TreasuresConfig).
	Цена = Price * множитель денег (как в PlayerTreasureManager). Деньги
	начисляются через PressConfig.SELL_DELAY — когда у клиента предмет упадёт в Sell.
	Остаток руды меньше WEIGHT_PER_ITEM крафтится с шансом, когда выгрузка закончена
	(см. PressConfig.RollRemainderRarity).
]]
local PressCraftHandler = {}

---- Knit Services
local PressService
local PlayerManagerService

---- Datas
local IDLE_WAIT = 0.25
local DEBUG = true -- логи крафта в Output (выключить, когда всё заработает)

---- State
local crafting = false
local threads = {} -- [player] = thread
local pending = {} -- [player] = { [craftId] = payout (EtNum) }
local nextCraftId = 0

-- Что крафтить следующим: oreId и вес, который уйдёт на предмет.
-- Сначала — руда, которой хватает на целый предмет (WEIGHT_PER_ITEM). Если такой
-- нет и игрок закончил выгрузку (REMAINDER_DELAY с последнего кусочка) — остаток
-- (< WEIGHT_PER_ITEM) любой руды, см. PressConfig.RollRemainderRarity.
local function findCraftableOre(player: Player): (string?, number)
	local ores = PressService:GetPressOres(player)
	for _, oreId in ipairs(OreConfig.Order) do
		local weight = tonumber(ores[oreId]) or 0
		local items = TreasuresConfig[OreConfig.Get(oreId).Rarity]
		if weight >= PressConfig.WEIGHT_PER_ITEM and items and #items > 0 then
			return oreId, PressConfig.WEIGHT_PER_ITEM
		end
	end

	local lastUnload = PressService.Components.PressUnloadHandler:GetLastUnloadTime(player)
	if os.clock() - lastUnload < PressConfig.REMAINDER_DELAY then
		return nil, 0
	end

	for _, oreId in ipairs(OreConfig.Order) do
		local weight = tonumber(ores[oreId]) or 0
		if weight > 0 then
			return oreId, math.min(weight, PressConfig.WEIGHT_PER_ITEM)
		end
	end
	return nil, 0
end

-- Строка «руда=вес» для логов.
local function describePress(player: Player): string
	local parts = {}
	for oreId, weight in pairs(PressService:GetPressOres(player)) do
		table.insert(parts, tostring(oreId) .. "=" .. tostring(weight))
	end
	return if #parts > 0 then table.concat(parts, ", ") else "пусто"
end

local function payOut(player: Player, payout)
	local money = PlayerManagerService:GetPlayerMoney(player)
	if not money then
		return
	end
	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.add(payout, money)))
end

function PressCraftHandler:_Sell(player: Player, craftId: number)
	local playerPending = pending[player]
	local payout = playerPending and playerPending[craftId]
	if not payout then
		return
	end
	playerPending[craftId] = nil

	payOut(player, payout)
end

function PressCraftHandler:_Craft(player: Player, oreId: string, weight: number)
	local ore = OreConfig.Get(oreId)
	local rarity = if weight >= PressConfig.WEIGHT_PER_ITEM
		then ore.Rarity
		else PressConfig.RollRemainderRarity(ore.Rarity, weight)
	local item = rarity and PressConfig.RollItem(rarity)

	PressService:AddPressOre(player, oreId, -weight)

	if DEBUG then
		print(
			string.format(
				"[Press] %s: %s x%d -> %s | осталось в прессе: %s",
				player.Name,
				oreId,
				weight,
				if item then item.Name .. " (" .. tostring(rarity) .. ")" else "НИЧЕГО (остаток сгорел)",
				describePress(player)
			)
		)
	end

	if not item then
		-- остаток самой низкой редкости не повезло — руда сгорает без предмета
		PressService.Client.ItemCrafted:Fire(player, oreId, weight)
		return
	end

	local cashMultiplier = PlayerManagerService:GetPlayerCashMultiplier(player) or 1
	local payout = EtNum.mul(item.Price, cashMultiplier)

	nextCraftId += 1
	local craftId = nextCraftId
	pending[player] = pending[player] or {}
	pending[player][craftId] = payout

	PressService.Client.ItemCrafted:Fire(player, oreId, weight, item.Name, rarity, EtNum.toString(payout))

	task.delay(PressConfig.SELL_DELAY, function()
		self:_Sell(player, craftId)
	end)
end

-- Один шаг цикла: ждём, пока есть что крафтить, выжидаем CraftSpeed, крафтим.
function PressCraftHandler:_Step(player: Player)
	if not PressService:IsProfileLoaded(player) or not findCraftableOre(player) then
		task.wait(IDLE_WAIT)
		return
	end

	task.wait(PressConfig.GetCraftInterval(PressService:GetPressLevel(player, "CraftSpeed")))

	-- за время ожидания игрок мог выйти
	if not player.Parent or not PressService:IsProfileLoaded(player) then
		return
	end

	-- перепроверка: за время ожидания могли выгрузить ещё руды
	local oreId, weight = findCraftableOre(player)
	if not oreId then
		return
	end

	self:_Craft(player, oreId, weight)
end

function PressCraftHandler:_Loop(player: Player)
	while player.Parent do
		-- любая ошибка — только в лог; без pcall поток умирал и крафт у игрока
		-- останавливался до перезахода
		local ok, err = pcall(self._Step, self, player)
		if not ok then
			warn("[PressCraftHandler] step failed:", err)
			task.wait(IDLE_WAIT)
		end
	end
end

function PressCraftHandler:_StartPlayer(player: Player)
	if threads[player] then
		return
	end
	threads[player] = task.spawn(self._Loop, self, player)
end

function PressCraftHandler:_StopPlayer(player: Player)
	local thread = threads[player]
	threads[player] = nil
	if thread and coroutine.status(thread) ~= "dead" then
		task.cancel(thread)
	end

	-- предметы, которые ещё ехали по конвейеру, продаём сразу, пока профиль жив
	local playerPending = pending[player]
	pending[player] = nil
	if playerPending then
		for _, payout in pairs(playerPending) do
			pcall(payOut, player, payout)
		end
	end
end

-- Запускается из PressService:KnitStart().
function PressCraftHandler:StartCrafting()
	if crafting then
		return
	end
	crafting = true

	for _, player in ipairs(Players:GetPlayers()) do
		self:_StartPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		self:_StartPlayer(player)
	end)
end

function PressCraftHandler.Start() end

function PressCraftHandler.Init()
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerRemoving:Connect(function(player)
		PressCraftHandler:_StopPlayer(player)
	end)
end

return PressCraftHandler
