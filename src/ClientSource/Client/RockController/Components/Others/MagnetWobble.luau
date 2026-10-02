local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	MagnetWobble — камни «чувствуют» магнит до удара (чисто визуально, локально).

	Настоящий хитбокс удара — серверный MagnetHitbox в персонаже
	(PlayerMagnetHitboxManager); он не меняется. Здесь — второй, ВНЕШНИЙ хитбокс:
	тот же центр, по горизонтали в OUTER_SCALE раз больше. Камень, попавший во
	внешний хитбокс, начинает:
	  * наклоняться к игроку (магнит тянет) вокруг своего основания;
	  * мелко дрожать (плавный шум, не случайные рывки).
	Сила растёт, чем ближе камень к настоящему хитбоксу (proximity 0..1) и чем
	меньше у него HP (повреждённый камень «вот-вот оторвётся»). Внутри настоящего
	хитбокса — максимум, пока камень не разобьётся; разрушение — прежнее
	(VisualEffects:ShatterRock).

	Анимация пишет абсолютный pivot от BasePivot (атрибут модели, RockVisualizer) —
	камень никогда не уползает. Пока идёт тряска от удара (VisualEffects:ShakeRock),
	дрожание пропускает кадры, чтобы не спорить за pivot.
]]

local MagnetWobble = {}

---- Datas
local OUTER_SCALE = 1.6 -- внешний хитбокс шире настоящего во столько раз (X/Z)
local OUTER_HEIGHT = 14 -- высота внешнего хитбокса, studs (настоящий почти плоский)
local SCAN_INTERVAL = 0.1 -- как часто искать камни во внешнем хитбоксе

local LEAN_MAX = math.rad(9) -- наклон к игроку на максимуме
local TREMBLE_ANGLE = math.rad(4.5) -- амплитуда дрожания (угол)
local TREMBLE_OFFSET = 0.18 -- амплитуда дрожания (сдвиг), studs
local TREMBLE_FREQ = 26 -- частота дрожания (выше — «вибрирует», но шум гладкий)
local NOISE_GAIN = 2 -- math.noise почти не выходит за ±0.5 — растягиваем до ~±1
-- Камень подтягивается к магниту: сдвиг к игроку и лёгкий подъём от земли
local PULL_OFFSET = 0.45 -- studs к игроку на максимуме
local PULL_LIFT = 0.25 -- studs вверх на максимуме
-- «Рывки» магнита: ритмичные плавные импульсы поверх постоянного наклона
local TUG_FREQ = 2.2 -- импульсов в секунду
local TUG_SHARPNESS = 3 -- чем больше, тем короче и резче импульс (остаётся гладким)
local TUG_STRENGTH = 0.45 -- импульс добавляет до +45% наклона и притяжения
local STRENGTH_CURVE = 0.7 -- <1: заметно уже у внешней границы зоны
local PULL_CAP = 1.8 -- потолок суммарного притяжения (наклон/сдвиг), см. step
local DAMAGE_BOOST = 0.8 -- до +80% силы у почти разбитого камня
local FADE_SPEED = 8 -- скорость нарастания/затухания силы (в секунду)

---- State
local player = Players.LocalPlayer
local RockController
local VisualEffects

type Wobble = {
	Model: Model,
	VisualData: any,
	Target: number, -- целевая сила 0..1 (по последнему скану)
	Strength: number, -- текущая (сглаженная) сила
	Seed: number,
	Toward: Vector3, -- горизонтальное направление от камня к игроку
}

local wobbling: { [Model]: Wobble } = {}
local scanTimer = 0

local PlayersRockFolder = workspace:WaitForChild("PlayersRock")
local rockFolderName = tostring(player.UserId) .. "_Rock"

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function rockKey(part: BasePart): string?
	local stripId, rockIndex = part:GetAttribute("StripId"), part:GetAttribute("RockIndex")
	if not stripId or not rockIndex then
		return nil
	end
	return tostring(stripId) .. "_" .. tostring(rockIndex)
end

-- 0 у внешней границы -> 1 на границе настоящего хитбокса и внутри него.
-- Хитбокс круглый (радиус Size.X / 2, см. PlayerMagnetHitboxManager:CollectTargets),
-- расстояние — от ближайшей точки камня (а не центра) до центра хитбокса, по горизонтали.
local function proximity(hitbox: BasePart, part: BasePart): number
	local p = part.CFrame:PointToObjectSpace(hitbox.Position)
	local halfX, halfZ = part.Size.X / 2, part.Size.Z / 2
	local dx = p.X - math.clamp(p.X, -halfX, halfX)
	local dz = p.Z - math.clamp(p.Z, -halfZ, halfZ)
	local gap = math.sqrt(dx * dx + dz * dz)
	local inner = hitbox.Size.X / 2
	-- доля пути от настоящего хитбокса до внешнего (0 = уже внутри настоящего)
	local t = math.max(gap - inner, 0) / math.max(inner * (OUTER_SCALE - 1), 0.01)
	return math.clamp(1 - t, 0, 1)
end

local function scan()
	local character = player.Character
	local hitbox = character and character:FindFirstChild("MagnetHitbox") :: BasePart?
	local rockFolder = PlayersRockFolder:FindFirstChild(rockFolderName)

	for _, w in pairs(wobbling) do
		w.Target = 0
	end
	if not hitbox or not rockFolder then
		return
	end

	params.FilterDescendantsInstances = { rockFolder }
	-- хитбоксы камней в группе "Rock_<userId>" — как и серверный запрос
	-- (PlayerMagnetHitboxManager:CollectTargets), ищем от группы магнита
	params.CollisionGroup = hitbox.CollisionGroup
	local outerSize = Vector3.new(hitbox.Size.X * OUTER_SCALE, OUTER_HEIGHT, hitbox.Size.Z * OUTER_SCALE)
	local parts = workspace:GetPartBoundsInBox(hitbox.CFrame, outerSize, params)

	for _, part in ipairs(parts) do
		local key = rockKey(part)
		local visualData = key and RockController.VisualizedRocks[key]
		local model = visualData and visualData.Model
		if model and model.Parent and not model:GetAttribute("Shattered") and model:GetAttribute("BasePivot") then
			local strength = proximity(hitbox, part)

			-- повреждённый камень дрожит сильнее
			local maxHp, hp = part:GetAttribute("MaxHp"), part:GetAttribute("Hp")
			if maxHp and hp and maxHp > 0 then
				strength *= 1 + DAMAGE_BOOST * (1 - math.clamp(hp / maxHp, 0, 1))
			end
			strength = math.clamp(strength, 0, 1 + DAMAGE_BOOST)

			local toward = (hitbox.Position - part.Position) * Vector3.new(1, 0, 1)
			local w = wobbling[model]
			if not w then
				w = {
					Model = model,
					VisualData = visualData,
					Target = 0,
					Strength = 0,
					Seed = math.random() * 1000,
					Toward = Vector3.xAxis,
				}
				wobbling[model] = w
			end
			w.Target = strength
			if toward.Magnitude > 0.01 then
				w.Toward = toward.Unit
			end
		end
	end
end

local function restore(model: Model)
	local base = model:GetAttribute("BasePivot")
	if model.Parent and base and not model:GetAttribute("Shattered") then
		model:PivotTo(base)
	end
end

local function step(dt: number)
	scanTimer -= dt
	if scanTimer <= 0 then
		scanTimer = SCAN_INTERVAL
		scan()
	end

	local now = os.clock()
	for model, w in pairs(wobbling) do
		if not model.Parent or model:GetAttribute("Shattered") then
			wobbling[model] = nil
			continue
		end

		-- плавное нарастание/затухание: камень «просыпается», а не дёргается
		w.Strength += (w.Target - w.Strength) * math.min(dt * FADE_SPEED, 1)
		if w.Target == 0 and w.Strength < 0.01 then
			wobbling[model] = nil
			restore(model)
			continue
		end

		if VisualEffects:IsHitShaking(model) then
			continue
		end

		local base: CFrame = model:GetAttribute("BasePivot")
		local bottom: Vector3 = model:GetAttribute("BaseBottom") or base.Position
		-- кривая силы: заметно уже у внешней границы, полная — у настоящего хитбокса
		local s = math.max(w.Strength, 0) ^ STRENGTH_CURVE
		local t = now * TREMBLE_FREQ + w.Seed

		-- «рывок» магнита: гладкий импульс 0..1 (синус в степени — короткий пик,
		-- без резких краёв), у каждого камня своя фаза
		local tug = (0.5 + 0.5 * math.sin((now * TUG_FREQ + w.Seed) * math.pi * 2)) ^ TUG_SHARPNESS
		-- потолок PULL_CAP: даже разбитый камень на пике рывка наклоняется
		-- максимум на LEAN_MAX * PULL_CAP (~16°) — эффектно, но не «падает»
		local pull = math.min(s * (1 + TUG_STRENGTH * tug), PULL_CAP)

		-- наклон верхушкой к игроку: поворот вокруг оси (вверх x направление)
		local axis = Vector3.yAxis:Cross(w.Toward)
		local lean = if axis.Magnitude > 0.01 then CFrame.fromAxisAngle(axis.Unit, LEAN_MAX * pull) else CFrame.identity

		-- дрожание: гладкий шум по трём осям (NOISE_GAIN — до полной амплитуды)
		local shake = TREMBLE_ANGLE * NOISE_GAIN * s
		local tremble = CFrame.Angles(
			math.noise(t, 0.3) * shake,
			math.noise(t, 4.1) * shake * 0.5,
			math.noise(t, 9.7) * shake
		)
		local jitter = Vector3.new(math.noise(t, 17.3), math.noise(t, 29.1) * 0.4, math.noise(t, 23.9))
			* TREMBLE_OFFSET
			* NOISE_GAIN
			* s

		-- притяжение: камень сдвигается к игроку и чуть отрывается от земли
		local drag = w.Toward * PULL_OFFSET * pull + Vector3.new(0, PULL_LIFT * pull, 0)

		-- поворот вокруг основания камня (а не pivot'а) — камень качается на месте
		local around = CFrame.new(bottom)
		model:PivotTo((around * lean * tremble * around:Inverse() * base) + jitter + drag)
	end
end

function MagnetWobble.Start()
	RunService.Heartbeat:Connect(step)
end

function MagnetWobble.Init()
	RockController = Knit.GetController("RockController")
	VisualEffects = require(script.Parent.VisualEffects)
end

return MagnetWobble
