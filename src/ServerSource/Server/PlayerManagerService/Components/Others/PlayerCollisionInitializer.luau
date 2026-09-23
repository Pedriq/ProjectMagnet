local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local PlayerCollisionInitializer = {}

---- Knit Services

---- Datas
local PlayersRockFolder = workspace:WaitForChild("PlayersRock")

---- Assets

local function setupCharacter(character, charGroup)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = charGroup
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = charGroup
		end
	end)
end

local function setUpCollisionGroupForPlayer(player, charGroup, rockGroup)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local otherRockGroup = "Rock_" .. otherPlayer.UserId
			local otherCharGroup = "Char_" .. otherPlayer.UserId

			if PhysicsService:IsCollisionGroupRegistered(otherRockGroup) then
				PhysicsService:CollisionGroupSetCollidable(charGroup, otherRockGroup, false)
			end

			if PhysicsService:IsCollisionGroupRegistered(otherCharGroup) then
				PhysicsService:CollisionGroupSetCollidable(rockGroup, otherCharGroup, false)
			end
		end
	end
end

function PlayerCollisionInitializer:InitCollisionForPlayer(player)
	local charGroup = "Char_" .. player.UserId
	local rockGroup = "Rock_" .. player.UserId

	if not PhysicsService:IsCollisionGroupRegistered(charGroup) then
		PhysicsService:RegisterCollisionGroup(charGroup)
	end

	if not PhysicsService:IsCollisionGroupRegistered(rockGroup) then
		PhysicsService:RegisterCollisionGroup(rockGroup)
	end

	PhysicsService:CollisionGroupSetCollidable(charGroup, rockGroup, true)

	setUpCollisionGroupForPlayer(player, charGroup, rockGroup)

	PhysicsService:CollisionGroupSetCollidable(rockGroup, "Default", true)

	if player.Character then
		setupCharacter(player.Character, charGroup)
	end

	player.CharacterAdded:Connect(function(character)
		setupCharacter(character, charGroup)
	end)

	local playerRockFolder = Instance.new("Folder")
	playerRockFolder.Name = player.UserId .. "_Rock"
	playerRockFolder.Parent = PlayersRockFolder
end

function PlayerCollisionInitializer.Start() end

function PlayerCollisionInitializer.Init() end

return PlayerCollisionInitializer
