-- Настройки глобальных (кросс-серверных) лидербордов по Magnetism и деньгам.
-- См. LeaderboardService.
local LeaderboardConfig = {
	TOP_COUNT = 100, -- сколько мест показываем на досках World<N>BazeZone.Leaderboards
	RENDER_DISTANCE = 65, -- studs: дальше этого расстояния до доски её текст не рисуется
	REFRESH_INTERVAL = 24 * 60 * 60, -- как часто пересобираем топ-100 на досках (раз в сутки)
	SYNC_INTERVAL = 5 * 60, -- как часто досылаем свежие Magnetism/Money игроков, ещё не вышедших, в OrderedDataStore
}

return LeaderboardConfig
