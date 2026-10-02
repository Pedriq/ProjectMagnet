local SoundService = game:GetService("SoundService")

--[[
	sfx — проигрывание звуков интерфейса/геймплея из SoundService.SFX.

	Все звуки лежат в SoundGroup SoundService.SFX (настраивается в Studio):
	  HoverUI — наведение на кнопку
	  Click   — клик по камню на экране + автоклики зон
	  ClickUI — клик по кнопке интерфейса
	  Buy     — покупка меча / доната
	  Sell    — продажа предметов
	  LevelUP — повышение уровня
	  Smash   — удар оружия (сигнал AttackHit)
	  Hit     — попадание по камню

	Фидбек-звуки (необязательные). Если Sound с таким именем нет в SoundService —
	играет FALLBACKS (существующий звук с другим pitch), так что всё звучит и без
	новых ассетов. Положи в SFX Sound с этим именем — он сразу заменит фоллбек:
	  OrePop       — кусочек руды долетел до игрока (pitch растёт цепочкой)
	  Shatter      — камень разрушен полностью
	  Crit         — критический клик
	  ComboUp      — новый рубеж комбо (10/25/50/100)
	  BagFull      — инвентарь переноски заполнен
	  RareDrop     — пресс сделал предмет Epic+
	  Collect      — забрал деньги с Collect
	  GoalReady    — хватает денег на следующий магнит
	  Checkpoint   — прошёл чекпоинт (руда сохранена)

	play(name, opts?) — полифония: каждый вызов берёт свободный клон из пула,
	поэтому частые клики не обрывают друг друга. opts:
	  pitch   — PlaybackSpeed (1 = как есть)
	  jitter  — случайный разброс pitch ±jitter (против «пулемётного» однообразия)
	  volume  — множитель громкости поверх громкости самого Sound
]]

local SFX = SoundService:WaitForChild("SFX") :: SoundGroup
SFX.Volume = 0.4

-- Точечные переопределения громкости отдельных звуков.
local VOLUME_OVERRIDES: { [string]: number } = {
	Hit = 0.15,
}

type Fallback = { name: string, pitch: number, volume: number? }

local FALLBACKS: { [string]: Fallback } = {
	OrePop = { name = "Click", pitch = 1.6, volume = 0.6 },
	Shatter = { name = "Smash", pitch = 0.7, volume = 1.4 },
	Crit = { name = "Smash", pitch = 1.35, volume = 1.3 },
	ComboUp = { name = "LevelUP", pitch = 1.5, volume = 0.6 },
	BagFull = { name = "ClickUI", pitch = 0.55, volume = 1.5 },
	RareDrop = { name = "LevelUP", pitch = 1.15 },
	Collect = { name = "Sell", pitch = 1.1 },
	GoalReady = { name = "Buy", pitch = 1.25 },
	Checkpoint = { name = "LevelUP", pitch = 1.4, volume = 0.4 },
}

-- Сколько одновременных копий одного звука держим.
local POOL_SIZE = 8
-- Не чаще, чем раз в столько секунд на имя — иначе 10 одинаковых звуков в одном
-- кадре просто складываются в клиппинг.
local MIN_INTERVAL = 0.025

type Pool = { clones: { Sound }, nextIndex: number, baseVolume: number, lastPlayed: number }

local pools: { [string]: Pool } = {}
local warned: { [string]: boolean } = {}

local poolFolder = Instance.new("Folder")
poolFolder.Name = "SFXPool"
poolFolder.Parent = SoundService

-- Sound может лежать прямо внутри SoundGroup (частый вариант), либо где угодно
-- в SoundService с проставленным свойством SoundGroup = SFX (тоже частый
-- вариант) — ищем сначала внутри группы, потом рекурсивно по всему SoundService.
local function findSound(name: string): Sound?
	local direct = SFX:FindFirstChild(name)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local anywhere = SoundService:FindFirstChild(name, true)
	if anywhere and anywhere:IsA("Sound") and not anywhere:IsDescendantOf(poolFolder) then
		return anywhere
	end

	return nil
end

local function getPool(name: string): Pool?
	local pool = pools[name]
	if pool then
		return pool
	end

	local sound = findSound(name)
	if sound == nil then
		return nil
	end

	if sound.SoundId == "" and not warned[name] then
		warned[name] = true
		warn(`[sfx] "{name}" найден, но у него не задан SoundId`)
	end

	local baseVolume = VOLUME_OVERRIDES[name] or sound.Volume
	local clones = {}
	for i = 1, POOL_SIZE do
		local clone = sound:Clone()
		clone.Name = name .. "_" .. i
		clone.SoundGroup = SFX
		clone.Looped = false
		clone.Parent = poolFolder
		table.insert(clones, clone)
	end

	pool = { clones = clones, nextIndex = 1, baseVolume = baseVolume, lastPlayed = 0 }
	pools[name] = pool
	return pool
end

export type Options = {
	pitch: number?,
	jitter: number?,
	volume: number?,
}

local function play(name: string, opts: Options?)
	local pitch = (opts and opts.pitch) or 1
	local volume = (opts and opts.volume) or 1

	local pool = getPool(name)
	if pool == nil then
		local fallback = FALLBACKS[name]
		if fallback then
			pool = getPool(fallback.name)
			pitch *= fallback.pitch
			volume *= fallback.volume or 1
		end
	end
	if pool == nil then
		if not warned[name] then
			warned[name] = true
			warn(`[sfx] "{name}" не найден в SoundService (искал в SFX и рекурсивно)`)
		end
		return
	end

	local now = os.clock()
	if now - pool.lastPlayed < MIN_INTERVAL then
		return
	end
	pool.lastPlayed = now

	local jitter = opts and opts.jitter
	if jitter and jitter > 0 then
		pitch *= 1 + (math.random() * 2 - 1) * jitter
	end

	local sound = pool.clones[pool.nextIndex]
	pool.nextIndex = pool.nextIndex % #pool.clones + 1

	sound.PlaybackSpeed = math.clamp(pitch, 0.1, 4)
	sound.Volume = pool.baseVolume * volume
	sound.TimePosition = 0
	sound:Play()
end

return {
	play = play,
}
