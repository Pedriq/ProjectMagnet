--[[
	OreConfig — типы руд (камней). ЕДИНСТВЕННОЕ место, где они перечислены.

	Id — идентификатор руды. Он же:
	  * атрибут "Section" на маркере в Workspace.StripMarkers (какая руда в полосе);
	  * ключ в инвентаре переноски и в профиле (profile.Ores[Id] = вес).
	Model — имя модели камня в ReplicatedStorage.Assets.Rock.
	MaxHp — HP одного камня.
	PieceWeight — вес одного отколотого кусочка (сегмента модели), идёт в инвентарь.
	PiecesPerItem — сколько кусочков пресс переплавляет в один предмет.
	WeightPerItem — вес руды на один предмет (= PieceWeight * PiecesPerItem).
	Rarity — редкость предметов, которые пресс делает из этой руды (ключ TreasuresConfig).
	  По умолчанию = Id; при переименовании руды (Common -> Copper) указать явно.
	Кусочки руды для визуала пресса — ReplicatedStorage.Assets.Ores.<Model>.

	Баланс веса: чем реже руда, тем тяжелее кусочек и тем больше кусочков на предмет —
	предмет Common весит 100, Ascendant — 2090. Вместимость растёт линейно
	(1200 + 100 за уровень Capacity, см. BaseStatsValues), так что прокачка Capacity
	важна всю игру: на старте влезает 12 предметов Common (16 камней Common, 10 камней
	Rare — зоны 1-3 без прокачки), но уже только ~8 камней Epic и ~1.5 камня Ascendant;
	чем дальше зона, тем чаще нужно на базу и тем нужнее Capacity.

	Чтобы заменить руды (CommonRock -> Copper и т.п.): поменять Id/Model здесь,
	атрибуты Section на маркерах и имена моделей в Assets.Rock. Код больше нигде
	имена руд не хранит. ВАЖНО: profile.Ores хранится по Id — при переименовании
	Id уже сохранённая у игроков руда останется под старым ключом.
]]

export type Ore = {
	Id: string,
	Model: string,
	MaxHp: number,
	PieceWeight: number,
	PiecesPerItem: number,
	WeightPerItem: number,
	Rarity: string,
}

-- Сколько кусочков (сегментов "1".."N" в модели камня) отваливается за весь камень.
-- Было 8, стало 15 — PieceWeight ниже пересчитан на коэффициент 8/15, чтобы
-- суммарный вес руды с одного камня (PieceWeight * PIECES_PER_ROCK) не изменился.
local PIECES_PER_ROCK = 15
local DEFAULT_PIECE_WEIGHT = 10
local DEFAULT_PIECES_PER_ITEM = 10

-- HP по порядку в списке: round(BASE_HP * RATIO ^ (index - 1) * MID_HP_MULT[index]). Баланс не финальный —
-- у конкретной руды можно задать MaxHp явно, тогда формула для неё не используется.
local BASE_HP = 10
local RATIO = 6.4

-- «Горб» середины игры: добавочный множитель HP по номеру руды в списке (1 = Common).
-- Зоны 1-3 не трогаем (старт быстрый, DamageCurve.SOFT_CAP рассчитан на HP зоны 3 — 410),
-- зоны 4-9 (Epic-Divine) заметно крепче — игрок дольше добирает силу в средних зонах, —
-- а дальше множитель плавно сходит к 1, так что поздние зоны остаются как были (игрок
-- просто приходит к ним позже). Крутить баланс середины — только этой таблицей.
local MID_HP_MULT: { [number]: number } = {
	[4] = 1.2, -- Epic
	[5] = 1.4, -- Legendary
	[6] = 1.55, -- Mythic
	[7] = 1.65, -- Secret
	[8] = 1.65, -- Godly
	[9] = 1.5, -- Divine
	[10] = 1.3, -- Celestial
	[11] = 1.15, -- Eternal
}

type Entry = {
	Id: string,
	Model: string,
	MaxHp: number?,
	PieceWeight: number?,
	PiecesPerItem: number?,
	Rarity: string?,
}

-- PieceWeight растёт ~x1.2 за редкость, PiecesPerItem — +2 каждые две редкости;
-- в комментарии — итоговый вес руды на один предмет (PieceWeight * PiecesPerItem).
-- PieceWeight пересчитан под PIECES_PER_ROCK = 15 (было 8, коэффициент 8/15),
-- чтобы вес одного камня (PieceWeight * PIECES_PER_ROCK) остался прежним.
local List: { Entry } = {
	{ Id = "Common", Model = "CommonRock", PieceWeight = 5, PiecesPerItem = 10 }, -- 50
	{ Id = "Uncommon", Model = "UncommonRock", PieceWeight = 6, PiecesPerItem = 10 }, -- 60
	{ Id = "Rare", Model = "RareRock", PieceWeight = 8, PiecesPerItem = 12 }, -- 96
	{ Id = "Epic", Model = "EpicRock", PieceWeight = 10, PiecesPerItem = 12 }, -- 120
	{ Id = "Legendary", Model = "LegendaryRock", PieceWeight = 12, PiecesPerItem = 14 }, -- 168
	{ Id = "Mythic", Model = "MythicRock", PieceWeight = 14, PiecesPerItem = 14 }, -- 196
	{ Id = "Secret", Model = "SecretRock", PieceWeight = 17, PiecesPerItem = 16 }, -- 272
	{ Id = "Godly", Model = "GodlyRock", PieceWeight = 20, PiecesPerItem = 16 }, -- 320
	{ Id = "Divine", Model = "DivineRock", PieceWeight = 24, PiecesPerItem = 18 }, -- 432
	{ Id = "Celestial", Model = "CelestialRock", PieceWeight = 29, PiecesPerItem = 18 }, -- 522
	{ Id = "Eternal", Model = "EternalRock", PieceWeight = 35, PiecesPerItem = 20 }, -- 700
	{ Id = "Cosmic", Model = "CosmicRock", PieceWeight = 43, PiecesPerItem = 20 }, -- 860
	{ Id = "Ascendant", Model = "AscendantRock", PieceWeight = 51, PiecesPerItem = 22 }, -- 1122
}

local OreConfig = {}

OreConfig.PIECES_PER_ROCK = PIECES_PER_ROCK

-- Порядок руд (как в List) — для UI/сортировок.
OreConfig.Order = {} :: { string }

local byId: { [string]: Ore } = {}

for index, entry in ipairs(List) do
	local pieceWeight = entry.PieceWeight or DEFAULT_PIECE_WEIGHT
	local piecesPerItem = entry.PiecesPerItem or DEFAULT_PIECES_PER_ITEM
	byId[entry.Id] = {
		Id = entry.Id,
		Model = entry.Model,
		MaxHp = entry.MaxHp or math.floor(BASE_HP * RATIO ^ (index - 1) * (MID_HP_MULT[index] or 1) + 0.5),
		PieceWeight = pieceWeight,
		PiecesPerItem = piecesPerItem,
		WeightPerItem = pieceWeight * piecesPerItem,
		Rarity = entry.Rarity or entry.Id,
	}
	table.insert(OreConfig.Order, entry.Id)
end

-- nil, если такой руды нет (например, опечатка в атрибуте Section у маркера).
function OreConfig.Get(id: string?): Ore?
	return id and byId[id] or nil
end

-- Сколько кусочков камня уже отвалилось при данном HP. Общая формула для сервера
-- (сколько руды начислить) и клиента (сколько сегментов модели отколоть) —
-- чтобы начисленное всегда совпадало с тем, что игрок видит.
function OreConfig.PiecesBroken(hp: number, maxHp: number): number
	if maxHp <= 0 then
		return PIECES_PER_ROCK
	end
	local hpPercent = math.clamp(hp / maxHp, 0, 1)
	return PIECES_PER_ROCK - math.ceil(PIECES_PER_ROCK * hpPercent)
end

return OreConfig
