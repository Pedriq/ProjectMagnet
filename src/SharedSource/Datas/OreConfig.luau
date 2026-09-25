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
	(300 + 100 за уровень Capacity, см. BaseStatsValues), так что прокачка Capacity
	нужна на протяжении всей игры: на старте влезает 3 предмета Common, но только
	~1 Legendary; для одного предмета Ascendant нужен ~19-й уровень.

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
local PIECES_PER_ROCK = 8
local DEFAULT_PIECE_WEIGHT = 10
local DEFAULT_PIECES_PER_ITEM = 10

-- HP по порядку в списке: round(BASE_HP * RATIO ^ (index - 1)). Баланс не финальный —
-- у конкретной руды можно задать MaxHp явно, тогда формула для неё не используется.
local BASE_HP = 10
local RATIO = 6.4

type Entry = {
	Id: string,
	Model: string,
	MaxHp: number?,
	PieceWeight: number?,
	PiecesPerItem: number?,
	Rarity: string?,
}

-- PieceWeight растёт ~x1.2 за редкость, PiecesPerItem — +2 каждые две редкости;
-- в комментарии — итоговый вес руды на один предмет.
local List: { Entry } = {
	{ Id = "Common", Model = "CommonRock", PieceWeight = 10, PiecesPerItem = 10 }, -- 100
	{ Id = "Uncommon", Model = "UncommonRock", PieceWeight = 12, PiecesPerItem = 10 }, -- 120
	{ Id = "Rare", Model = "RareRock", PieceWeight = 15, PiecesPerItem = 12 }, -- 180
	{ Id = "Epic", Model = "EpicRock", PieceWeight = 18, PiecesPerItem = 12 }, -- 216
	{ Id = "Legendary", Model = "LegendaryRock", PieceWeight = 22, PiecesPerItem = 14 }, -- 308
	{ Id = "Mythic", Model = "MythicRock", PieceWeight = 26, PiecesPerItem = 14 }, -- 364
	{ Id = "Secret", Model = "SecretRock", PieceWeight = 32, PiecesPerItem = 16 }, -- 512
	{ Id = "Godly", Model = "GodlyRock", PieceWeight = 38, PiecesPerItem = 16 }, -- 608
	{ Id = "Divine", Model = "DivineRock", PieceWeight = 45, PiecesPerItem = 18 }, -- 810
	{ Id = "Celestial", Model = "CelestialRock", PieceWeight = 55, PiecesPerItem = 18 }, -- 990
	{ Id = "Eternal", Model = "EternalRock", PieceWeight = 65, PiecesPerItem = 20 }, -- 1300
	{ Id = "Cosmic", Model = "CosmicRock", PieceWeight = 80, PiecesPerItem = 20 }, -- 1600
	{ Id = "Ascendant", Model = "AscendantRock", PieceWeight = 95, PiecesPerItem = 22 }, -- 2090
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
		MaxHp = entry.MaxHp or math.floor(BASE_HP * RATIO ^ (index - 1) + 0.5),
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
