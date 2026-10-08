local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local AnalyticsService = game:GetService("AnalyticsService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AnalyticsConfig = require(ReplicatedStorage.SharedSource.Datas.AnalyticsConfig)
local RateLimiter = require(ReplicatedStorage.SharedSource.Utilities.RateLimiter)

--[[
	AnalyticsFunnelService — воронки аналитики (см. SharedSource/Datas/AnalyticsConfig).

	  Tutorial    — шаги обучения. Клиент сообщает, до какого шага дошёл игрок (TutorialStep); сервер проверяет
	                имя, порядок (шаг только вперёд) и пишет воронку; завершение пишет САМ сервер
	                (PlayerManagerService:CompleteTutorial). Каждый запуск обучения — свой funnelSessionId.
	  Checkpoints — чекпоинты (CheckpointHandler): шаг = номер чекпоинта, один раз за заход игрока.

	Дополнительно к воронкам — кастомные события (для разбивок, которых нет в воронке):
	  TutorialStepCompleted {Step, Skipped, Seconds}, TutorialDropOff {Step, Seconds} (вышел, не завершив обучение),
	  CheckpointReached {Checkpoint, Rebirth, Level} (каждый проход, в т.ч. повторные круги),
	  CheckpointSessionEnd {Highest, Rebirth} (на выходе игрока — где он остановился).

	Всё в pcall: аналитика никогда не ломает геймплей. Клиентский метод только один (TutorialStep) —
	он влияет лишь на статистику, не на экономику.
]]
local FunnelService = Knit.CreateService({
	Name = "AnalyticsFunnelService",
	Client = {},
})

local ProfileService
local PlayerManagerService

type TutorialRun = { SessionId: string, Step: number, StepAt: number, Completed: boolean }
type CheckpointRun = { SessionId: string, Reached: { [number]: boolean }, Highest: number, Rebirth: number }

local tutorialRuns: { [Player]: TutorialRun } = {}
local checkpointRuns: { [Player]: CheckpointRun } = {}

local function guid(): string
	return HttpService:GenerateGUID(false)
end

local function logStep(player: Player, funnel: string, sessionId: string, step: number, stepName: string)
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, sessionId, step, stepName)
	end)
	if not ok then
		warn("[AnalyticsFunnel] LogFunnelStepEvent failed:", err)
	end
end

local function logEvent(player: Player, eventName: string, value: number, fields: { [string]: any }?)
	local stringFields
	if fields then
		stringFields = {}
		for key, v in pairs(fields) do
			stringFields[key] = tostring(v)
		end
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value, stringFields)
	end)
	if not ok then
		warn("[AnalyticsFunnel] LogCustomEvent failed:", err)
	end
end

-- === Tutorial ====================================================================
local function writeTutorialSteps(player: Player, run: TutorialRun, target: number)
	local now = os.clock()
	for step = run.Step + 1, target do
		local skipped = step ~= target
		logStep(player, AnalyticsConfig.TutorialFunnel, run.SessionId, step, AnalyticsConfig.TutorialStepName(step))
		-- предыдущий шаг считается завершённым, когда достигнут следующий
		if step > 1 then
			logEvent(player, "TutorialStepCompleted", step - 1, {
				Step = AnalyticsConfig.TutorialStepName(step - 1),
				Skipped = skipped,
				Seconds = math.floor(now - run.StepAt),
			})
		end
		run.StepAt = now
	end
	run.Step = target
end

-- Игрок дошёл до шага `stepName`. Первый вызов открывает воронку (и пишет "Started").
function FunnelService:TutorialStep(player: Player, stepName: string)
	local target = AnalyticsConfig.TutorialStepIndex(stepName)
	-- Completed сервер пишет сам; из клиента принимаем только игровые шаги
	if not target or stepName == "Completed" then
		return
	end
	-- обучение уже пройдено — воронка не нужна
	if ProfileService:GetData(player, { "Tutorial", "Completed" }) == true then
		return
	end

	local run = tutorialRuns[player]
	if not run then
		run = { SessionId = guid(), Step = 0, StepAt = os.clock(), Completed = false }
		tutorialRuns[player] = run
		writeTutorialSteps(player, run, 1) -- Started
	end
	if run.Completed or target <= run.Step then
		return
	end
	writeTutorialSteps(player, run, target)
end

function FunnelService:TutorialCompleted(player: Player)
	local run = tutorialRuns[player]
	if not run or run.Completed then
		return -- обучение в этой сессии не начиналось (старый профиль / тихий финиш) — в воронку не пишем
	end
	writeTutorialSteps(player, run, #AnalyticsConfig.TutorialSteps)
	run.Completed = true
end

function FunnelService.Client:TutorialStep(player: Player, stepName: any)
	if type(stepName) ~= "string" or #stepName > 24 or not RateLimiter.Allow(player, "TutorialStep", 0.2) then
		return
	end
	self.Server:TutorialStep(player, stepName)
end

-- === Checkpoints =================================================================
-- Игрок прошёл чекпоинт `index` (число из имени парта, nil — не удалось определить).
function FunnelService:CheckpointReached(player: Player, index: number?, partName: string)
	local run = checkpointRuns[player]
	if not run then
		run = { SessionId = guid(), Reached = {}, Highest = 0, Rebirth = 0 }
		checkpointRuns[player] = run
	end

	local rebirth = PlayerManagerService:GetPlayerRebirths(player) or 0
	local level = PlayerManagerService:GetPlayerLevel(player) or 1
	run.Rebirth = rebirth -- запоминаем: на выходе профиль может быть уже освобождён
	logEvent(player, "CheckpointReached", index or 0, { Checkpoint = partName, Rebirth = rebirth, Level = level })

	if index and index >= 1 and index == math.floor(index) and not run.Reached[index] then
		run.Reached[index] = true
		run.Highest = math.max(run.Highest, index)
		logStep(player, AnalyticsConfig.CheckpointFunnel, run.SessionId, index, string.format("CP_%02d", index))
	end
end

-- === Выход игрока ====================================================================
local function onPlayerRemoving(player: Player)
	local tutorial = tutorialRuns[player]
	if tutorial and not tutorial.Completed then
		logEvent(player, "TutorialDropOff", tutorial.Step, {
			Step = AnalyticsConfig.TutorialStepName(tutorial.Step),
			Seconds = math.floor(os.clock() - tutorial.StepAt),
		})
	end
	local checkpoints = checkpointRuns[player]
	if checkpoints then
		logEvent(
			player,
			"CheckpointSessionEnd",
			checkpoints.Highest,
			{ Highest = checkpoints.Highest, Rebirth = checkpoints.Rebirth }
		)
	end
end

function FunnelService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		-- ошибки аналитики не пробрасываем; состояние чистим в любом случае
		local ok, err = pcall(onPlayerRemoving, player)
		if not ok then
			warn("[AnalyticsFunnel] PlayerRemoving failed:", err)
		end
		tutorialRuns[player] = nil
		checkpointRuns[player] = nil
	end)
end

function FunnelService:KnitInit()
	ProfileService = Knit.GetService("ProfileService")
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return FunnelService
