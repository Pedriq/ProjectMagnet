local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WorldSpawnHandler = {}

---- Datas
-- Кулдаун на телепорт «на базу» (на игрока), чтобы нельзя было спамить кнопкой.
local TELEPORT_COOLDOWN = 1
-- Приподнять над партом спавна, чтобы персонаж не застревал в полу/платформе.
local SPAWN_HEIGHT_OFFSET = 3

---- State
local lastTeleport = {} -- [userId] = os.clock()

---- Assets
-- Точка спавна мира, в котором сейчас игрок. Пока мир один: берём
-- RespawnLocation игрока, иначе первый SpawnLocation в воркспейсе.
-- (Мультимир позже: выбирать спавн по миру игрока.)
function WorldSpawnHandler:GetWorldSpawn(player: Player): BasePart?
	local respawn = player.RespawnLocation
	if respawn and respawn:IsA("BasePart") then
		return respawn
	end

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") then
			return inst
		end
	end

	return nil
end

-- Телепортировать игрока на респавн его мира.
function WorldSpawnHandler:TeleportToWorldSpawn(player: Player)
	local now = os.clock()
	local last = lastTeleport[player.UserId]
	if last and now - last < TELEPORT_COOLDOWN then
		return
	end
	lastTeleport[player.UserId] = now

	local character = player.Character
	if not character or not character.PrimaryPart then
		return
	end

	local spawnPart = self:GetWorldSpawn(player)
	if not spawnPart then
		warn("[WorldSpawnHandler] нет SpawnLocation для телепорта игрока", player.Name)
		return
	end

	local target = spawnPart.CFrame * CFrame.new(0, spawnPart.Size.Y / 2 + SPAWN_HEIGHT_OFFSET, 0)
	character:PivotTo(target)
end

function WorldSpawnHandler.Start() end

function WorldSpawnHandler.Init()
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player.UserId] = nil
	end)
end

return WorldSpawnHandler
