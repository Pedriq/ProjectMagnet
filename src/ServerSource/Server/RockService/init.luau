local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local RockService = Knit.CreateService({
	Name = "RockService",
	StripData = {},
	ActiveStrips = {},
	-- [userId] = стоит ли игрок сейчас в зоне майнинга — пишет и держит
	-- актуальным Components.RockZoneWatcher (true = игрок ВНУТРИ Workspace.RockZone,
	-- реальная зона ZonePlus). НЕ дистанция до StripMarkers (та годится только
	-- как грубый предфильтр для подгрузки хитбоксов, см. KnitStart ниже).
	PlayerInZone = {},
	Client = {
		-- (player, inZone: boolean) — состояние сменилось.
		ZoneChanged = Knit.CreateSignal(),
	},
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
RockService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	RockService.Components[v.Name] = require(v)
end
RockService.GetComponent = require(componentsFolder["Get()"])
RockService.SetComponent = require(componentsFolder["Set()"])

---- Knit Services

function RockService:GetStripData()
	return self.StripData
end

function RockService:ResetPlayerHitboxes(player)
	self.Components.RockHitboxManager:ResetPlayer(player)
end

function RockService:KnitStart()
	task.spawn(function()
		while true do
			for _, player in pairs(game.Players:GetPlayers()) do
				-- pcall на игрока: транзиентная ошибка (напр. стрип-дата ещё не
				-- готова на старте) не должна ронять весь цикл и морозить камни всем.
				local ok, err = pcall(function()
					local nearbyStrips = self.Components.RockDistanceCheck:CheckDistance(player)
					self.Components.RockHitboxManager:UpdatePlayer(player, nearbyStrips)
				end)

				if not ok then
					warn(("[RockService] UpdatePlayer failed for %s: %s"):format(player.Name, tostring(err)))
				end
			end

			task.wait(0.5)
		end
	end)
end

function RockService:KnitInit()
	---- Components Initializer
	componentsInitializer(script)

	self.StripData = self.Components.RockStripInitializer:InitRockStripData()

	Players.PlayerRemoving:Connect(function(player)
		self.Components.RockHitboxManager:CleanupPlayer(player)
		self.PlayerInZone[player.UserId] = nil
	end)
end

return RockService
