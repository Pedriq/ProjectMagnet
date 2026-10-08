--[[
	OfflineConfig — офлайн-награды (OfflineService): пока игрока не было в игре, пресс продолжает
	переплавлять руду из очереди, а клики по экрану симулируются с фиксированной частотой.

	Всё считает сервер при заходе (по os.time() последнего выхода из профиля); клиент только
	показывает панель и просит забрать награду.
]]
local OfflineConfig = {}

-- Короче этого отсутствие не считается (быстрый релог, телепорт между серверами).
OfflineConfig.MIN_AWAY_SECONDS = 20

-- Один симулируемый клик раз в столько секунд (ручной клик игрока гораздо быстрее — офлайн слабее).
OfflineConfig.CLICK_INTERVAL = 2

-- Потолок периода награды. Дольше отсутствовал — награда всё равно как за этот период:
-- нельзя уйти на недели и вернуться с горой силы или пропустить прогрессию.
-- Потолок действует и на пресс (меньше предметов за период), и на клики (MAX_CLICKS ниже).
OfflineConfig.MAX_OFFLINE_SECONDS = 4 * 60 * 60

OfflineConfig.MAX_CLICKS = math.floor(OfflineConfig.MAX_OFFLINE_SECONDS / OfflineConfig.CLICK_INTERVAL)

-- Сколько кликов дал период reward (секунды), с учётом потолка.
function OfflineConfig.ClicksFor(seconds: number): number
	local capped = math.clamp(seconds, 0, OfflineConfig.MAX_OFFLINE_SECONDS)
	return math.min(math.floor(capped / OfflineConfig.CLICK_INTERVAL), OfflineConfig.MAX_CLICKS)
end

return OfflineConfig
