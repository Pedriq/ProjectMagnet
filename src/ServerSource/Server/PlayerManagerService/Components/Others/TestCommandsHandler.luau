local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

--[[
	TestCommandsHandler — чат-команды для баланса. Работают ТОЛЬКО в Studio
	(RunService:IsStudio()), в реальной игре команды не подключаются.

	/money <сумма> — начислить себе деньги. Сумма — обычное число ("10000")
	или EtNum-scientific ("1e50").
]]

local TestCommandsHandler = {}

---- Knit Services
local PlayerManagerService

local function onChatted(player: Player, message: string)
	local amountText = message:match("^/money%s+(%S+)$")
	if not amountText then
		return
	end

	local ok, amount = pcall(EtNum.convert, amountText)
	if not ok then
		warn("[TestCommands] не смог разобрать сумму:", amountText)
		return
	end

	local current = PlayerManagerService:GetPlayerMoney(player) or "0"
	local newMoney = EtNum.toString(EtNum.add(current, amount))

	PlayerManagerService:ChangePlayerMoney(player, newMoney)
	print(("[TestCommands] %s: /money %s -> баланс %s"):format(player.Name, amountText, newMoney))
end

local function hook(player: Player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

function TestCommandsHandler.Start()
	if not RunService:IsStudio() then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end

	Players.PlayerAdded:Connect(hook)
end

function TestCommandsHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return TestCommandsHandler
