local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local RockDistanceCheck = {}

---- Knit Services
local RockService

---- Datas
local RADIUS = 80

local function getNearbyStrips(strips, playerX, radius)
	local result = {}

	local minX = playerX - radius
	local maxX = playerX + radius

	for _, strip in ipairs(strips) do
		if strip.xPos >= minX and strip.xPos <= maxX then
			result[#result + 1] = strip
		end
	end

	return result
end

---- Assets
function RockDistanceCheck:CheckDistance(player)
	-- Без Wait: этот вызов идёт из ОБЩЕГО цикла RockService по всем игрокам. Игрок без персонажа (только зашёл /
	-- респавнится / вышел во время ожидания) заморозил бы появление камней у ВСЕХ, пока не заспавнится (а вышедший —
	-- навсегда). Нет персонажа — просто нет ближних полос в этом тике.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		return {}
	end

	return getNearbyStrips(RockService.StripData, root.Position.X, RADIUS)
end

function RockDistanceCheck.Start() end

function RockDistanceCheck.Init()
	RockService = Knit.GetService("RockService")
end

return RockDistanceCheck
