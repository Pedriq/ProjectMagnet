local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	CheckpointHandler — парты в Workspace.Checkpoints.

	Проход сквозь чекпоинт сохраняет несомую руду в профиль (как Save-зона),
	но каждый чекпоинт срабатывает для игрока только 1 раз — до ресета.
	Ресет — после полного круга Entrance -> Save (см. SaveItemsZoneHandler).

	Визуал локальный (CheckpointController): пройденный чекпоинт становится
	прозрачным только для этого игрока, на ресет — возвращается.
]]
local CheckpointHandler = {}

---- Knit Services
local PlayerManagerService

---- Datas
local FOLDER_NAME = "Checkpoints"

---- State
local passed = {} -- [userId] = { [BasePart] = true }

function CheckpointHandler:_OnTouched(part: BasePart, hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local playerPassed = passed[player.UserId]
	if not playerPassed then
		playerPassed = {}
		passed[player.UserId] = playerPassed
	end
	if playerPassed[part] then
		return
	end
	playerPassed[part] = true

	-- сколько руды сохраняем — для эффекта «+N ORE SAVED» на клиенте
	-- (после SaveCarriedOres инвентарь переноски уже пуст)
	local saved = PlayerManagerService:GetCarryInfo(player).Count
	PlayerManagerService:SaveCarriedOres(player)
	PlayerManagerService.Client.CheckpointPassed:Fire(player, part, saved)
end

function CheckpointHandler:_Bind(part: Instance)
	if not part:IsA("BasePart") then
		return
	end

	part.Touched:Connect(function(hit)
		self:_OnTouched(part, hit)
	end)
end

-- Все чекпоинты снова активны для игрока (и снова видимы у него на клиенте).
function CheckpointHandler:Reset(player: Player)
	passed[player.UserId] = nil
	PlayerManagerService.Client.CheckpointsReset:Fire(player)
end

-- Запускается из PlayerManagerService:KnitStart().
function CheckpointHandler:StartWatching()
	task.spawn(function()
		local folder = workspace:WaitForChild(FOLDER_NAME, 30)
		if not folder then
			warn("[CheckpointHandler] не найден Workspace." .. FOLDER_NAME)
			return
		end

		for _, part in ipairs(folder:GetDescendants()) do
			self:_Bind(part)
		end
		folder.DescendantAdded:Connect(function(part)
			self:_Bind(part)
		end)
	end)
end

function CheckpointHandler.Start() end

function CheckpointHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")

	Players.PlayerRemoving:Connect(function(player)
		passed[player.UserId] = nil
	end)
end

return CheckpointHandler
