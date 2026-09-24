local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local SaveItemsZoneHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas
-- Парты сейв-зон в воркспейсе — этот CollectionService-тег.
local ZONE_TAG = "SaveItemsZone"
-- Парт-вход: пройти сквозь него -> игрок получает флаг READY_ATTR.
local ENTRANCE_TAG = "Entrance"
-- Флаг на игроке (атрибут): прошёл вход и ждёт сейв-зону. Сгорает после сейва —
-- чтобы сохранить снова, нужно опять пройти через вход.
local READY_ATTR = "CanSaveItems"
-- Как часто опрашивать сейв-зоны.
local CHECK_INTERVAL = 1
-- Дебаунс на .Touched входа (на игрока).
local ENTRANCE_DEBOUNCE = 0.5

---- State
local watching = false
local entranceDebounce = {} -- [userId] = os.clock()

---- Assets
-- Сохранить принесённую руду в профиль и вернуть игроку разбитые камни.
function SaveItemsZoneHandler:_ProcessPlayer(player: Player)
	PlayerManagerService:SaveCarriedOres(player)
	PlayerManagerService:ResetPlayerRock(player)
end

-- HRP игроков, у которых стоит флаг READY_ATTR, + обратная карта part -> player.
local function collectReadyRoots()
	local roots = {}
	local rootToPlayer = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute(READY_ATTR) then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				table.insert(roots, root)
				rootToPlayer[root] = player
			end
		end
	end

	return roots, rootToPlayer
end

function SaveItemsZoneHandler:_Tick()
	local zones = CollectionService:GetTagged(ZONE_TAG)
	if #zones == 0 then
		return
	end

	local roots, rootToPlayer = collectReadyRoots()
	if #roots == 0 then
		return
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	params.MaxParts = #roots

	local processed = {}
	for _, zone in ipairs(zones) do
		if zone:IsA("BasePart") then
			for _, part in ipairs(workspace:GetPartsInPart(zone, params)) do
				local player = rootToPlayer[part]
				if player and not processed[player] then
					processed[player] = true

					local ok, err = pcall(function()
						self:_ProcessPlayer(player)
					end)
					if ok then
						-- флаг сгорел: следующий сейв — только после нового прохода входа
						player:SetAttribute(READY_ATTR, false)
					else
						warn("[SaveItemsZoneHandler] _ProcessPlayer failed:", err)
					end
				end
			end
		end
	end
end

-- Пройти сквозь Entrance -> повесить флаг READY_ATTR.
function SaveItemsZoneHandler:_BindEntrance(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local now = os.clock()
		local last = entranceDebounce[player.UserId]
		if last and now - last < ENTRANCE_DEBOUNCE then
			return
		end
		entranceDebounce[player.UserId] = now

		player:SetAttribute(READY_ATTR, true)
	end)
end

-- Запускается из PlayerManagerService:KnitStart().
function SaveItemsZoneHandler:StartWatching()
	if watching then
		return
	end
	watching = true

	for _, part in ipairs(CollectionService:GetTagged(ENTRANCE_TAG)) do
		self:_BindEntrance(part)
	end
	CollectionService:GetInstanceAddedSignal(ENTRANCE_TAG):Connect(function(part)
		self:_BindEntrance(part)
	end)

	task.spawn(function()
		while watching do
			task.wait(CHECK_INTERVAL)

			local ok, err = pcall(function()
				self:_Tick()
			end)
			if not ok then
				warn("[SaveItemsZoneHandler] tick error:", err)
			end
		end
	end)
end

function SaveItemsZoneHandler.Start() end

function SaveItemsZoneHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute(READY_ATTR, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		entranceDebounce[player.UserId] = nil
	end)
end

return SaveItemsZoneHandler
