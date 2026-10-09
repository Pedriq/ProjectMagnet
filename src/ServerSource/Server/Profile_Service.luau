local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Knit = require(ReplicatedStorage.Packages.Knit)
local RateLimiter = require(ReplicatedStorage.SharedSource.Utilities.RateLimiter)

local ProfileService = Knit.CreateService({
	Name = "ProfileService",
	Client = {
		GetData = Knit.CreateSignal(),

		--[[
			@description Use this for client to reduce network receive data, this updates DataController.Data
		
			Note: If you use :Connect() and want to retrieve updated data, ensure to add a task.wait() 
			at least for the DataController.Data to update.
		]]
		UpdateSpecificData = Knit.CreateSignal(),
	},

	UpdateSpecificData = Signal.new(),
	-- Fire(player) — профиль загружен и лежит в Profiles (OfflineService считает награду за отсутствие).
	ProfileLoaded = Signal.new(),
	-- Fire(player) — СИНХРОННО перед EndSession при выходе: профиль ещё в Profiles (финальная синхронизация
	-- лидербордов и т.п.). После этого Profiles[player] == nil, а Data больше не принадлежит серверу.
	ProfileReleasing = Signal.new(),
})

local ActualProfileStore =
	require(ServerScriptService:WaitForChild("ServerSource"):WaitForChild("Externals"):WaitForChild("ProfileStore"))
local ProfileTemplate = require(ReplicatedStorage.SharedSource.Datas.ProfileTemplate)

local PlayerProfileStore

local Profiles = {} -- [player] = profile
ProfileService.Profiles = Profiles

-- Состояние жизненного цикла (чистится в PlayerRemoving):
local loading: { [Player]: boolean } = {} -- StartSessionAsync уже идёт (защита от двойной загрузки)
local loadFailed: { [Player]: boolean } = {} -- загрузка не удалась → игрок кикнут, ждать нечего
local leaving: { [Player]: boolean } = {} -- PlayerRemoving уже прошёл
local waiters: { [Player]: { thread } } = {} -- потоки, ждущие профиль
local warned: { [Player]: boolean } = {} -- «профиль недоступен» уже выводилось для игрока

local function resumeWaiters(player)
	local list = waiters[player]
	if not list then
		return
	end
	waiters[player] = nil
	for _, thread in ipairs(list) do
		task.spawn(thread)
	end
end

-- Профиль недоступен: если игрок уже уходит/кикнут — это штатно (тихо). Если игрок ещё на сервере, а профиля нет
-- (сбой загрузки / сессия отобрана) — это настоящая проблема, пишем ОДИН раз на игрока, а не на каждый вызов.
local function reportUnavailable(player, context: string)
	if leaving[player] or not player:IsDescendantOf(Players) or warned[player] then
		return
	end
	warned[player] = true
	warn(("Profile data not found for player: %s (%s)"):format(player.Name, context))
end

local function DataSuccessfullyLoaded(player)
	-- Called when a profile is successfully loaded
	ProfileService.ProfileLoaded:Fire(player)
end

local function HandlePlayerAdded(player)
	if loading[player] or Profiles[player] then
		return
	end
	loading[player] = true

	-- pcall: ошибка DataStore не должна оставить игрока в игре без профиля с вечно ждущими системами.
	-- Данные при сбое НЕ подменяются шаблоном: профиля нет → игрок кикается, ничего не записывается.
	local ok, profile = pcall(PlayerProfileStore.StartSessionAsync, PlayerProfileStore, "Player_" .. player.UserId)
	loading[player] = nil
	if not ok then
		warn(`[ProfileService] StartSessionAsync failed for {player.Name} ({player.UserId}): {tostring(profile)}`)
		profile = nil
	end

	if profile ~= nil then
		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing variables from ProfileTemplate

		-- Add MetaData for backwards compatibility
		if not profile.MetaData then
			profile.MetaData = {
				ProfileCreateTime = profile.FirstSessionTime,
				SessionLoadCount = profile.SessionLoadCount,
				ActiveSession = profile.Session,
			}
		end

		-- Офлайн-награды (OfflineService): LastSeen обновляется при КАЖДОМ сохранении профиля — автосейв,
		-- выход, остановка сервера. Иначе после падения/шатдауна в профиле остался бы старый (или нулевой,
		-- то есть «первая сессия») LastSeen, и награда не посчиталась бы.
		profile.OnSave:Connect(function()
			local offline = profile.Data.Offline
			if offline then
				offline.LastSeen = os.time()
			end
		end)

		profile.OnSessionEnd:Connect(function()
			if Profiles[player] == profile then
				Profiles[player] = nil
			end
			-- The profile could've been loaded on another Roblox server
			if not leaving[player] then
				player:Kick()
			end
		end)

		if player:IsDescendantOf(Players) and not leaving[player] then
			Profiles[player] = profile
			DataSuccessfullyLoaded(player)
			resumeWaiters(player)
		else
			-- Player left before the profile loaded: данные не трогаем, просто отпускаем сессию
			profile:EndSession()
			resumeWaiters(player)
		end
	else
		-- The profile couldn't be loaded possibly due to other
		-- Roblox servers trying to load this profile at the same time
		loadFailed[player] = true
		resumeWaiters(player)
		if not leaving[player] then
			warn(`[ProfileService] profile not loaded for {player.Name} ({player.UserId}) — kicking, nothing written`)
			player:Kick("Не удалось загрузить данные. Попробуйте зайти ещё раз.")
		end
	end
end

local function HandlePlayerRemoving(player)
	leaving[player] = true
	local profile = Profiles[player]
	if profile ~= nil then
		ProfileService.ProfileReleasing:Fire(player)
		-- время выхода для офлайн-наград (OfflineService): пишем до EndSession, чтобы попало в сохранение
		local offline = profile.Data.Offline
		if offline then
			offline.LastSeen = os.time()
		end
		profile:EndSession()
	end
	resumeWaiters(player)

	-- состояние чистим позже: обработчики PlayerRemoving других сервисов ещё могут спросить профиль
	task.delay(10, function()
		if not player:IsDescendantOf(Players) then
			loading[player], loadFailed[player], leaving[player], warned[player], waiters[player] =
				nil, nil, nil, nil, nil
		end
	end)
end

function ProfileService:IsProfileLoaded(player): boolean
	return player ~= nil and Profiles[player] ~= nil
end

-- Ждёт профиль без опроса: true — готов; false — игрок ушёл / загрузка не удалась (вызывающий обязан остановиться).
function ProfileService:WaitUntilProfileLoaded(player): boolean
	while not Profiles[player] do
		if leaving[player] or loadFailed[player] or not player:IsDescendantOf(Players) then
			return false
		end
		local list = waiters[player]
		if not list then
			list = {}
			waiters[player] = list
		end
		table.insert(list, coroutine.running())
		coroutine.yield()
	end
	return true
end

function ProfileService:GetProfile(player)
	if player == nil then
		warn("Player instance is nil when getting profile")
		return nil
	end

	if not Profiles[player] then
		ProfileService:WaitUntilProfileLoaded(player)
	end

	local profile = Profiles[player]
	return profile, profile and profile.Data
end

function ProfileService:ChangeData(player, redirectories, newValue)
	local profile, profileData = ProfileService:GetProfile(player)

	if not profileData then
		reportUnavailable(player, "ChangeData")
		return
	end

	local directData = profileData

	-- Navigate through the redirectories path
	for i = 1, #redirectories do
		if not directData[redirectories[i]] and i ~= #redirectories then
			local redirectoriesPath = "profileData"
			for j = 1, i do
				redirectoriesPath = redirectoriesPath .. "." .. redirectories[j]
			end
			error(
				"'"
					.. redirectoriesPath
					.. "' table does not exist. ALWAYS PREVENT THIS BY MAKING TABLES INSIDE PROFILETEMPLATE."
			)
			return
		end

		if i ~= #redirectories then
			directData = directData[redirectories[i]]
		end
	end

	-- Set the new value
	directData[redirectories[#redirectories]] = newValue

	-- Fire update signals
	ProfileService.Client.UpdateSpecificData:Fire(player, redirectories, newValue)
	ProfileService.UpdateSpecificData:Fire(player, redirectories, newValue)
end

function ProfileService:GetData(player, redirectories)
	local profile, profileData = ProfileService:GetProfile(player)

	if not profileData then
		reportUnavailable(player, "GetData")
		return nil
	end

	local directData = profileData

	for i = 1, #redirectories do
		if directData[redirectories[i]] == nil then
			return nil
		end

		directData = directData[redirectories[i]]
	end

	return directData
end

-- Раньше тут был Client:GetOtherPlayer_ProfileData(player, otherPlayer): любой клиент мог вытянуть ПОЛНЫЙ профиль
-- любого игрока (деньги, покупки, чеки) и подвесить серверные потоки произвольным аргументом. Клиент его нигде
-- не использовал — удалён. Свои данные клиент получает снапшотом GetData и точечными UpdateSpecificData.

function ProfileService.Client:GetProfileAge(player)
	if not RateLimiter.Allow(player, "GetProfileAge", 2) then
		return 0
	end
	local profile = ProfileService:GetProfile(player)
	if not profile then
		return 0
	end

	local profileAge = os.time() - profile.FirstSessionTime
	return profileAge
end

function ProfileService:KnitStart()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(HandlePlayerAdded, player)
	end

	-- Connect player events
	Players.PlayerAdded:Connect(HandlePlayerAdded)
	Players.PlayerRemoving:Connect(HandlePlayerRemoving)

	-- Handle client data requests
	-- Не чаще раза в 2 с и не больше одного ожидающего запроса на игрока: клиент шлёт GetData один раз при старте,
	-- а спам из эксплойта иначе плодил бы потоки WaitUntilProfileLoaded и слал бы полный профиль в цикле.
	local getDataPending: { [Player]: boolean } = {}
	ProfileService.Client.GetData:Connect(function(player)
		if getDataPending[player] or not RateLimiter.Allow(player, "GetData", 2) then
			return
		end
		getDataPending[player] = true

		ProfileService:WaitUntilProfileLoaded(player)
		local _, profileData = ProfileService:GetProfile(player)
		getDataPending[player] = nil
		if profileData and player.Parent then
			ProfileService.Client.GetData:Fire(player, profileData)
		end
	end)
end

-- ==== Special for Rock game
function ProfileService:AddItem(player, itemId, itemData)
	local profile, profileData = ProfileService:GetProfile(player)
	if not profileData then
		reportUnavailable(player, "AddItem")
		return false
	end

	if profileData.Items[itemId] then
		warn("Item with id " .. itemId .. " already exists for player: " .. player.Name)
		return false
	end

	profileData.Items[itemId] = itemData

	ProfileService.Client.UpdateSpecificData:Fire(player, { "Items", "Add" }, itemId, itemData)
	ProfileService.UpdateSpecificData:Fire(player, { "Items", "Add" }, itemId, itemData)

	return true
end

function ProfileService:RemoveItem(player, itemId)
	local profile, profileData = ProfileService:GetProfile(player)
	if not profileData then
		reportUnavailable(player, "RemoveItem")
		return false
	end

	if not profileData.Items[itemId] then
		warn("Item with id " .. tostring(itemId) .. " not found for player: " .. player.Name)
		return false
	end

	profileData.Items[itemId] = nil

	ProfileService.Client.UpdateSpecificData:Fire(player, { "Items", "Remove" }, itemId)
	ProfileService.UpdateSpecificData:Fire(player, { "Items", "Remove" }, itemId)

	return true
end

function ProfileService:ClearItems(player)
	local profile, profileData = ProfileService:GetProfile(player)
	if not profileData then
		reportUnavailable(player, "ClearItems")
		return
	end

	profileData.Items = {}

	ProfileService.Client.UpdateSpecificData:Fire(player, { "Items", "Clear" })
	ProfileService.UpdateSpecificData:Fire(player, { "Items", "Clear" })
end

function ProfileService:KnitInit()
	PlayerProfileStore = ActualProfileStore.New("OriginalData1", ProfileTemplate)
end

return ProfileService
