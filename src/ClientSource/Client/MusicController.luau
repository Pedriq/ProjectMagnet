local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AudioSettings = require(ReplicatedStorage.ClientSource.audioSettings)

--[[
	MusicController — фоновая музыка: SoundService.Music (SoundGroup) с треками Music1, Music2, Music3 играют по кругу
	Music1 -> Music2 -> Music3 -> Music1 -> ... бесконечно, строго по одному треку за раз.

	  * ОДИН поток-проигрыватель и по одному соединению Ended на трек, создаются ровно один раз (KnitStart вызывается
	    единожды, повторный запуск защищён флагом) — дублей воспроизведения и подписок не возникает;
	  * перед стартом все треки останавливаются (в Studio у Sound мог остаться Playing = true), Looped выключается;
	  * мягкий вход и выход громкости (FADE_TIME) на стыках — без щелчков, переход между треками чистый;
	  * трек, который не загрузился (нет ассета/нулевая длина), пропускается; если не загрузился ни один — пауза и новая
	    попытка, а не цикл вхолостую;
	  * общая громкость — у SoundGroup Music (база MUSIC_BASE в audioSettings × ползунок Settings); громкость самих Sound контроллер не
	    меняет, лишь масштабирует Sound.Volume на время фейдов и возвращает исходное значение.
]]
local MusicController = Knit.CreateController({
	Name = "MusicController",
})

---- Datas
local GROUP_NAME = "Music"
local TRACK_NAMES = { "Music1", "Music2", "Music3" }
-- Общая громкость музыки — ТОЛЬКО через SoundGroup Music (громкость отдельных треков не трогаем). SFX-группа стоит на 1.2
-- (см. sfx.luau), поэтому музыка — тихий фон: звуки игры остаются на первом плане. Подстройка — это число.
local FADE_TIME = 1.2 -- секунд плавного входа/выхода на каждом треке
local TICK = 0.05 -- шаг обновления громкости во время фейдов
local LOAD_TIMEOUT = 10
local RETRY_DELAY = 10 -- пауза, если не удалось загрузить ни один трек
local END_GRACE = 3 -- сек сверх длины трека, после которых зависший трек считается закончившимся

---- State
local started = false

type Track = {
	Sound: Sound,
	BaseVolume: number,
	Ended: boolean,
	Connection: RBXScriptConnection,
}

local function findGroup(): SoundGroup?
	local group = SoundService:WaitForChild(GROUP_NAME, LOAD_TIMEOUT)
	if group and group:IsA("SoundGroup") then
		return group
	end
	-- на случай, если группа названа так же, но лежит глубже
	local nested = SoundService:FindFirstChild(GROUP_NAME, true)
	if nested and nested:IsA("SoundGroup") then
		return nested
	end
	return nil
end

local function findSound(group: SoundGroup, name: string): Sound?
	local sound = group:FindFirstChild(name) or SoundService:FindFirstChild(name, true)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

-- Загрузить аудио; true — трек готов к воспроизведению.
local function ensureLoaded(sound: Sound): boolean
	if not sound.IsLoaded then
		pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
	end
	if not sound.IsLoaded then
		local deadline = os.clock() + LOAD_TIMEOUT
		while not sound.IsLoaded and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	return sound.IsLoaded and sound.TimeLength > 0
end

-- Играть один трек до конца. Возвращает, когда трек закончился (Ended) или завис дольше длины + END_GRACE.
local function playTrack(track: Track)
	local sound = track.Sound
	track.Ended = false
	sound.TimePosition = 0
	sound.Volume = 0
	sound:Play()

	local length = sound.TimeLength
	local startedAt = os.clock()
	local hardStop = length + END_GRACE

	while not track.Ended and os.clock() - startedAt < hardStop and sound.Parent do
		-- громкость: плавный вход от начала и плавный выход к концу трека
		local position = sound.TimePosition
		local fadeIn = if FADE_TIME > 0 then position / FADE_TIME else 1
		local fadeOut = if FADE_TIME > 0 then (length - position) / FADE_TIME else 1
		sound.Volume = track.BaseVolume * math.clamp(math.min(fadeIn, fadeOut), 0, 1)
		task.wait(TICK)
	end

	sound:Stop()
	sound.Volume = track.BaseVolume
end

function MusicController:KnitStart()
	if started then
		return -- плейлист уже запущен: второй поток дал бы двойное воспроизведение
	end
	started = true

	task.spawn(function()
		local group = findGroup()
		if not group then
			warn(`[Music] в SoundService нет SoundGroup "{GROUP_NAME}" — музыка не запущена`)
			return
		end


		-- собираем плейлист в заданном порядке; по соединению Ended на трек, один раз
		local playlist: { Track } = {}
		local allRouted = true -- все найденные треки уже были направлены в группу Music до нас
		for _, name in ipairs(TRACK_NAMES) do
			local sound = findSound(group, name)
			if not sound then
				warn(`[Music] не найден трек "{name}" — пропускаю`)
				continue
			end

			sound.Looped = false
			-- Трек должен идти через группу Music, иначе слайдер на него не действует. Если раньше он в группу
			-- не направлялся, его громкость играла «как есть» — ниже база группы станет 1, чтобы не стало тише.
			if sound.SoundGroup ~= group then
				allRouted = false
				sound.SoundGroup = group
			end
			sound:Stop()

			local track = { Sound = sound, BaseVolume = sound.Volume, Ended = false } :: any
			track.Connection = sound.Ended:Connect(function()
				track.Ended = true
			end)
			table.insert(playlist, track)
		end

		AudioSettings.bindMusic(group, allRouted) -- громкость группы = база × ползунок Settings

		if #playlist == 0 then
			warn("[Music] в группе нет ни одного трека из списка — музыка не запущена")
			return
		end

		-- Music1 -> Music2 -> Music3 -> Music1 -> ...
		local index = 1
		local failures = 0
		while true do
			local track = playlist[index]
			if ensureLoaded(track.Sound) then
				failures = 0
				playTrack(track)
			else
				failures += 1
				warn(`[Music] "{track.Sound.Name}" не загрузился — пропускаю`)
				if failures >= #playlist then
					failures = 0
					task.wait(RETRY_DELAY) -- ничего не играет: ждём и пробуем снова, не крутим цикл вхолостую
				end
			end
			index = index % #playlist + 1
		end
	end)
end

function MusicController:KnitInit() end

return MusicController
