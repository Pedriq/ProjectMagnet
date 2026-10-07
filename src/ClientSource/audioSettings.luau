local TweenService = game:GetService("TweenService")
local vide = require(game:GetService("ReplicatedStorage").Packages.Vide)

local source = vide.source

--[[
	audioSettings — пользовательская громкость музыки и звуков (окно Settings).

	Значение 0..1 — множитель к базовой громкости SoundGroup (Music / SFX); 1 = как задумано
	геймдизайном, 0 = тишина. Громкость самих Sound не трогаем.

	  musicVolume / sfxVolume — vide-источники (читает UI слайдера);
	  setMusic / setSfx — слайдер: громкость группы меняется сразу и плавно (короткий твин);
	  bindMusic(group, tracksWereRouted) / bindSfx(group) — вызывают MusicController и sfx.
	  ДО привязки группа не трогается вообще (ни слайдер, ни load()): значение лишь запоминается
	  и применяется в момент bind, так что музыка/звуки не глохнут из-за порядка запуска.

	База громкости группы:
	  SFX   — 3 (звуки на первом плане, см. sfx);
	  Music — 0.015, если треки и раньше шли через группу Music; 1, если раньше они в группу не
	          направлялись и играли на собственной громкости (MusicController направляет их в группу,
	          чтобы слайдер работал, — база 1 оставляет прежний уровень).

	Сохранение между сессиями: окно Settings шлёт значение на сервер (profile.Settings), а
	UI.data при загрузке профиля вызывает load().
]]

local MUSIC_BASE_ROUTED = 0.015 -- тихий фон (треки уже шли через группу Music)
local MUSIC_BASE_UNROUTED = 1 -- треки играли на своей громкости: группа её не меняет
local SFX_BASE = 3 -- было 1.2: звуки были тихими даже на 100% (SoundGroup.Volume допускает до 10)
local TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local musicVolume = source(1)
local sfxVolume = source(1)

type Channel = {
	base: number,
	group: SoundGroup?,
	tween: Tween?,
}

local music: Channel = { base = MUSIC_BASE_ROUTED }
local sfxChannel: Channel = { base = SFX_BASE }

local function apply(channel: Channel, value: number, instant: boolean?)
	local group = channel.group
	if not group then
		return -- ещё не привязана: применится в bind
	end
	local target = channel.base * value
	if channel.tween then
		channel.tween:Cancel()
		channel.tween = nil
	end
	if instant or math.abs(group.Volume - target) < 1e-6 then
		group.Volume = target
		return
	end
	local tween = TweenService:Create(group, TWEEN, { Volume = target })
	channel.tween = tween
	tween:Play()
end

local function setMusic(v: number)
	v = math.clamp(v, 0, 1)
	musicVolume(v)
	apply(music, v)
end

local function setSfx(v: number)
	v = math.clamp(v, 0, 1)
	sfxVolume(v)
	apply(sfxChannel, v)
end

-- Применить сохранённые значения из профиля (без обратной записи на сервер).
local function load(musicValue: number, sfxValue: number)
	setMusic(musicValue)
	setSfx(sfxValue)
end

local function bindMusic(group: SoundGroup, tracksWereRouted: boolean?)
	music.group = group
	music.base = if tracksWereRouted == false then MUSIC_BASE_UNROUTED else MUSIC_BASE_ROUTED
	apply(music, musicVolume(), true)
end

local function bindSfx(group: SoundGroup)
	sfxChannel.group = group
	apply(sfxChannel, sfxVolume(), true)
end

return {
	musicVolume = musicVolume,
	sfxVolume = sfxVolume,
	setMusic = setMusic,
	setSfx = setSfx,
	load = load,
	bindMusic = bindMusic,
	bindSfx = bindSfx,
}
