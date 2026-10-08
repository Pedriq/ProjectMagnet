local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)

--[[
	PressCollectHandler — сбор денег за проданные прессом предметы.

	PressCraftHandler не зачисляет деньги сразу, а копит их в
	profile.Press.Unclaimed. Пока HumanoidRootPart игрока над
	Workspace.HydraulicPress.Collect (см. PressConfig.COLLECT_NAMES), накопленное
	переносится в Stats.Money, а клиенту уходит MoneyCollected.

	Владельцам Game Pass «OP Auto Collect» (AutoCollectPassConfig) деньги зачисляются сами,
	без захода на Collect; MoneyCollected для них не шлём (баннер/тряска на каждый предмет
	были бы спамом) — рост Money виден по «+$X».
]]
local PressCollectHandler = {}

---- Knit Services
local PressService
local PlayerManagerService

---- Datas
local TICK = 0.2

---- State
local watching = false

function PressCollectHandler:_CollectFor(player: Player, silent: boolean?)
	local unclaimed = PressService:GetUnclaimed(player)
	if not EtNum.me(unclaimed, "0") then
		return
	end

	local money = PlayerManagerService:GetPlayerMoney(player)
	if not money then
		return
	end

	PressService:SetUnclaimed(player, "0")
	PlayerManagerService:ChangePlayerMoney(player, EtNum.toString(EtNum.add(unclaimed, money)))
	-- unclaimed уже EtNum-строка из профиля (EtNum.toString принимает только EtNum-объект)
	if not silent then
		PressService.Client.MoneyCollected:Fire(player, unclaimed)
	end
end

function PressCollectHandler:_Tick()
	local onPads = PressService:GetPlayersOnPads(PressConfig.COLLECT_NAMES)
	for player in pairs(onPads) do
		local ok, err = pcall(self._CollectFor, self, player)
		if not ok then
			warn("[PressCollectHandler] collect failed:", err)
		end
	end

	-- OP Auto Collect: остальные игроки с пассом
	for _, player in ipairs(Players:GetPlayers()) do
		if not onPads[player] and PressService:IsProfileLoaded(player) and PlayerManagerService:HasAutoCollect(player) then
			local ok, err = pcall(self._CollectFor, self, player, true)
			if not ok then
				warn("[PressCollectHandler] auto-collect failed:", err)
			end
		end
	end
end

-- Запускается из PressService:KnitStart().
function PressCollectHandler:StartWatching()
	if watching then
		return
	end
	watching = true

	task.spawn(function()
		while watching do
			task.wait(TICK)
			local ok, err = pcall(self._Tick, self)
			if not ok then
				warn("[PressCollectHandler] tick error:", err)
			end
		end
	end)
end

function PressCollectHandler.Start() end

function PressCollectHandler.Init()
	PressService = Knit.GetService("PressService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PressCollectHandler
