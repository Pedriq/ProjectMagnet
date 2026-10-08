--[[
	AnalyticsConfig — воронки аналитики (AnalyticsFunnelService -> Roblox AnalyticsService).

	В Creator Dashboard -> Analytics -> Funnels воронку можно смотреть и по сессиям (funnelSessionId),
	и по уникальным пользователям — отдельная логика для этого не нужна.

	Tutorial — воронка обучения. Шаги идут по порядку; номер шага = позиция в TutorialSteps.
	  "Started" — обучение реально началось;
	  имена игровых шагов совпадают со STAGES в ClientSource/UI/tutorial (клиент присылает имя);
	  "Completed" — обучение завершено (пишет сервер в CompleteTutorial, клиенту не доверяем).
	Шаг, который игрок перепрыгнул (выполнил заранее — обучение это допускает), записывается вместе с
	пропущенными, чтобы воронка оставалась последовательной; пропущенные помечены в событии
	TutorialStepCompleted (Skipped).

	Checkpoints — воронка чекпоинтов. Шаг = номер чекпоинта (число из имени парта/модели в Workspace.Checkpoints),
	один раз за заход игрока (повторные круги после ресета в воронку не пишутся, но попадают в событие
	CheckpointReached).
]]
local AnalyticsConfig = {}

AnalyticsConfig.TutorialFunnel = "Tutorial"
AnalyticsConfig.TutorialSteps = {
	"Started",
	"Magnetism",
	"Ore",
	"Base",
	"Unload",
	"Collect",
	"Save",
	"Buy",
	"Free",
	"Capacity",
	"Finish",
	"Completed",
}

AnalyticsConfig.CheckpointFunnel = "Checkpoints"

-- Имя шага вида "03_Ore": при сортировке в дашборде порядок сохраняется.
function AnalyticsConfig.TutorialStepName(step: number): string
	return string.format("%02d_%s", step, AnalyticsConfig.TutorialSteps[step] or "?")
end

function AnalyticsConfig.TutorialStepIndex(name: any): number?
	if type(name) ~= "string" then
		return nil
	end
	return table.find(AnalyticsConfig.TutorialSteps, name)
end

return AnalyticsConfig
