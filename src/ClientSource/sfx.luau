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

	play(name) не клонирует Sound — повторный вызов перезапускает тот же
	инстанс (PlayLocalSound), это ожидаемо для частых кликов кликера.
]]

local SFX = SoundService:WaitForChild("SFX") :: SoundGroup
SFX.Volume = 0.4

-- Точечные переопределения громкости отдельных звуков.
local VOLUME_OVERRIDES: { [string]: number } = {
	Hit = 0.15,
}

local sounds: { [string]: Sound } = {}

-- Sound может лежать прямо внутри SoundGroup (частый вариант), либо где угодно
-- в SoundService с проставленным свойством SoundGroup = SFX (тоже частый
-- вариант) — ищем сначала внутри группы, потом рекурсивно по всему SoundService.
local function findSound(name: string): Sound?
	local direct = SFX:FindFirstChild(name)
	if direct and direct:IsA("Sound") then
		return direct
	end

	local anywhere = SoundService:FindFirstChild(name, true)
	if anywhere and anywhere:IsA("Sound") then
		return anywhere
	end

	return nil
end

local function play(name: string)
	local sound = sounds[name]
	if sound == nil then
		sound = findSound(name)
		if sound == nil then
			warn(`[sfx] "{name}" не найден в SoundService (искал в SFX и рекурсивно)`)
			return
		end
		sounds[name] = sound

		local volumeOverride = VOLUME_OVERRIDES[name]
		if volumeOverride ~= nil then
			sound.Volume = volumeOverride
		end

		if sound.SoundId == "" then
			warn(`[sfx] "{name}" найден, но у него не задан SoundId`)
		end
	end

	SoundService:PlayLocalSound(sound)
end

return {
	play = play,
}
