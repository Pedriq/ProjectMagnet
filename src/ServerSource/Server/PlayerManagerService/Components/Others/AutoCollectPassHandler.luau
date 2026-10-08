local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AutoCollectPassConfig = require(ReplicatedStorage.SharedSource.Datas.AutoCollectPassConfig)

--[[
	AutoCollectPassHandler — Game Pass «OP Auto Collect» (см. AutoCollectPassConfig).

	Покупка подтверждается Roblox (PromptGamePassPurchaseFinished), как у донат-мечей
	(MagnetGamePassPurchaseHandler): флаг profile.AutoCollectPass = true пишется сразу,
	клиент получает его через ProfileService.UpdateSpecificData и мгновенно прячет кнопку.
	При входе владение восстанавливается живым запросом UserOwnsGamePassAsync — на случай
	покупки пасса вне сессии (страница игры). Сам эффект — в PressCollectHandler:
	деньги пресса зачисляются автоматически, без захода на Collect.
]]
local AutoCollectPassHandler = {}

---- Knit Services
local PlayerManagerService
local ProfileService

function AutoCollectPassHandler:Owns(player: Player): boolean
	return ProfileService:GetData(player, { "AutoCollectPass" }) == true
end

function AutoCollectPassHandler:Grant(player: Player)
	if not self:Owns(player) then
		ProfileService:ChangeData(player, { "AutoCollectPass" }, true)
	end
end

function AutoCollectPassHandler:PromptPurchase(player: Player)
	if self:Owns(player) then
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, AutoCollectPassConfig.GamePassId)
end

local function restoreForPlayer(player: Player)
	task.spawn(function()
		-- GetData ждёт загрузки профиля
		if AutoCollectPassHandler:Owns(player) then
			return
		end
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AutoCollectPassConfig.GamePassId)
		end)
		if ok and owns then
			AutoCollectPassHandler:Grant(player)
		elseif not ok then
			warn(`[AutoCollectPass] UserOwnsGamePassAsync упал для {player.Name}:`, owns)
		end
	end)
end

function AutoCollectPassHandler.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if gamePassId ~= AutoCollectPassConfig.GamePassId or not wasPurchased then
			return
		end
		AutoCollectPassHandler:Grant(player)
	end)

	-- Уже подключённые игроки (Play Solo в Studio)
	for _, player in ipairs(Players:GetPlayers()) do
		restoreForPlayer(player)
	end
end

function AutoCollectPassHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ProfileService = Knit.GetService("ProfileService")

	Players.PlayerAdded:Connect(restoreForPlayer)
end

return AutoCollectPassHandler
