local Players = game:GetService("Players")

-- Анимация удара по камню. Играет на каждый РЕАЛЬНЫЙ автоудар (см.
-- RockController:HitRock — фирится сервером на фактическое попадание, не на
-- клик мышью).
--
-- 2026-09-18: несколько анимаций в пуле — каждый удар берётся случайная из них (см.
-- PlayAttack), чтобы удары не выглядели одинаково подряд.
local ATTACK_ANIM_IDS = {
	"rbxassetid://78789755018021",
	"rbxassetid://99159763076927",
}

local module = {}

local player = Players.LocalPlayer

-- Всё, что привязано к текущему персонажу. Сбрасывается при респавне.
local state = {
	character = nil,
	animator = nil,
	-- Один AnimationTrack на каждый id из ATTACK_ANIM_IDS (тот же порядок) —
	-- загружаются раз на спавн, дальше PlayAttack просто выбирает индекс.
	tracks = {},
}

-- Верхний предел ускорения — на случай экстремально короткого кулдауна
-- (если кто-то уменьшит BaseStatsValues.AttacksCooldawn сильнее задуманного), визуально
-- всё равно нечитаемо быстрее.
local MAX_SPEED = 8

local function buildTracks()
	if not state.animator then
		return
	end

	state.tracks = {}
	for _, animId in ipairs(ATTACK_ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = animId

		local track = state.animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		-- Один клик — один удар, без зацикливания.
		track.Looped = false

		table.insert(state.tracks, track)
	end
end

local function onCharacter(character: Instance)
	state.character = character
	local humanoid = character:WaitForChild("Humanoid", 10)
	state.animator = humanoid and humanoid:WaitForChild("Animator", 10)
	state.tracks = {}
	buildTracks()
end

function module.Init()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

--[[
	Вызывается RockController:HitRock на каждый реальный автоудар — cooldown это
	фиксированный кулдаун атаки (BaseStatsValues.AttacksCooldawn): скорость
	анимации подгоняется под него, чтобы взмах укладывался между ударами.
]]
function module:PlayAttack(cooldown: number?)
	local character = player.Character
	if not character or character ~= state.character then
		return -- персонаж сменился, ждём onCharacter
	end
	if #state.tracks == 0 then
		buildTracks()
	end
	if #state.tracks == 0 then
		return
	end

	-- Случайная анимация из пула на каждый удар — для разнообразия.
	local track = state.tracks[math.random(1, #state.tracks)]

	-- Длина анимации может быть 0 до первой реальной загрузки ассета — тогда
	-- просто играем на обычной скорости.
	local length = track.Length
	local speed = 1
	if cooldown and cooldown > 0 and length and length > 0 then
		speed = math.clamp(length / cooldown, 1, MAX_SPEED)
	end

	-- Останавливаем ВСЕ треки пула, а не только выбранный — если в прошлый раз выпала
	-- другая анимация и ещё не доиграла (удары чаще, чем длина анимации), она наложилась бы
	-- на новую.
	for _, otherTrack in ipairs(state.tracks) do
		otherTrack:Stop(0)
	end
	track:Play(0.05, 1, speed)
end

return module
