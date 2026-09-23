local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RockGeometry = require(ReplicatedStorage.SharedSource.Object.RockGeometry)
local RockHitboxManager = {}

local PlayersRockFolder = workspace:WaitForChild("PlayersRock")

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local RockService
local PlayerManagerService

---- Datas

---- Assets
function RockHitboxManager:CreateStripHitboxes(player, strip)
	local playerFolder = PlayersRockFolder:FindFirstChild(player.UserId .. "_Rock")

	if not playerFolder then
		return
	end

	local stripFolder = Instance.new("Folder")
	stripFolder.Name = strip.stripId
	stripFolder.Parent = playerFolder

	local metrics = RockGeometry.GetMetrics(strip.section)
	local startZ = strip.zPos - RockGeometry.GetRowWidth() / 2

	for rockIndex = 1, strip.rockCount do
		if PlayerManagerService:GetRockState(player.UserId, strip.stripId, rockIndex).cut then
			continue
		end

		local hitbox = Instance.new("Part")

		hitbox.Name = "Rock_" .. rockIndex
		hitbox.Size = metrics.hitboxSize

		local z = startZ + (rockIndex - 1) * metrics.spacing

		hitbox.CFrame = CFrame.new(strip.xPos, RockGeometry.GetGroundY() + metrics.hitboxSize.Y / 2, z)

		hitbox.Anchored = true
		hitbox.Transparency = 1
		hitbox.CanCollide = true
		hitbox.CanTouch = false
		hitbox.CanQuery = true

		hitbox.CollisionGroup = "Rock_" .. player.UserId

		hitbox.Parent = stripFolder

		hitbox.CollisionGroup = "Rock_" .. player.UserId
		CollectionService:AddTag(hitbox, "RockHitbox")
		hitbox:SetAttribute("StripId", strip.stripId)
		hitbox:SetAttribute("RockIndex", rockIndex)
		hitbox:SetAttribute("Section", strip.section)
		hitbox:SetAttribute("MaxHp", strip.rockMaxHp)
		hitbox:SetAttribute("Hp", PlayerManagerService:GetRockState(player.UserId, strip.stripId, rockIndex).hp)
	end
end

function RockHitboxManager:DestroyStripHitboxes(player, stripId)
	local playerFolder = PlayersRockFolder:FindFirstChild(player.UserId .. "_Rock")

	if not playerFolder then
		return
	end

	local stripFolder = playerFolder:FindFirstChild(stripId)

	if stripFolder then
		stripFolder:Destroy()
	end
end

-- Игрок вышел: сносим его папку с хитбоксами целиком и забываем активные полосы.
-- Иначе парты остаются в Workspace, а после DataCleaner:CleanPlayerCollisionGrooup
-- (разрегистрация "Rock_<id>") сваливаются в группу Default и начинают
-- коллайдиться с персонажами оставшихся игроков — невидимые стены на полосе,
-- где вышедший стоял. Стейл ActiveStrips[userId] к тому же не даёт пересоздать
-- хитбоксы, если тот же userId зайдёт снова.
function RockHitboxManager:CleanupPlayer(player)
	local playerFolder = PlayersRockFolder:FindFirstChild(player.UserId .. "_Rock")

	if playerFolder then
		playerFolder:Destroy()
	end

	RockService.ActiveStrips[player.UserId] = nil
end

function RockHitboxManager:ResetPlayer(player)
	local playerFolder = PlayersRockFolder:FindFirstChild(player.UserId .. "_Rock")

	if playerFolder then
		playerFolder:ClearAllChildren()
	end

	-- Забываем, какие полосы уже были построены для игрока, чтобы ближайшие
	-- на следующем тике UpdatePlayer пересоздались заново — уже с сброшенным HP.
	RockService.ActiveStrips[player.UserId] = {}
end

function RockHitboxManager:UpdatePlayer(player, nearbyStrips)
	local userId = player.UserId

	RockService.ActiveStrips[userId] = RockService.ActiveStrips[userId] or {}

	local current = RockService.ActiveStrips[userId]
	local nearby = {}

	for _, strip in ipairs(nearbyStrips) do
		nearby[strip.stripId] = strip

		if not current[strip.stripId] then
			self:CreateStripHitboxes(player, strip)

			current[strip.stripId] = true
		end
	end

	for stripId in pairs(current) do
		if not nearby[stripId] then
			self:DestroyStripHitboxes(player, stripId)

			current[stripId] = nil
		end
	end
end

function RockHitboxManager.Start() end

function RockHitboxManager.Init()
	RockService = Knit.GetService("RockService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return RockHitboxManager
