--[[
	OreConfig — типы руд (камней). ЕДИНСТВЕННОЕ место, где они перечислены.

	Id — идентификатор руды. Он же:
	  * атрибут "Section" на маркере в Workspace.StripMarkers (какая руда в полосе);
	  * ключ в инвентаре переноски и в профиле (profile.Ores[Id] = вес).
	Model — имя модели камня в ReplicatedStorage.Assets.Rock.
	MaxHp — HP одного камня.
	PieceWeight — вес одного отколотого кусочка (сегмента модели), идёт в инвентарь.

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
}

-- Сколько кусочков (сегментов "1".."N" в модели камня) отваливается за весь камень.
local PIECES_PER_ROCK = 8
local DEFAULT_PIECE_WEIGHT = 10

-- HP по порядку в списке: round(BASE_HP * RATIO ^ (index - 1)). Баланс не финальный —
-- у конкретной руды можно задать MaxHp явно, тогда формула для неё не используется.
local BASE_HP = 10
local RATIO = 6.4

local List: { { Id: string, Model: string, MaxHp: number?, PieceWeight: number? } } = {
	{ Id = "Common", Model = "CommonRock" },
	{ Id = "Uncommon", Model = "UncommonRock" },
	{ Id = "Rare", Model = "RareRock" },
	{ Id = "Epic", Model = "EpicRock" },
	{ Id = "Legendary", Model = "LegendaryRock" },
	{ Id = "Mythic", Model = "MythicRock" },
	{ Id = "Secret", Model = "SecretRock" },
	{ Id = "Godly", Model = "GodlyRock" },
	{ Id = "Divine", Model = "DivineRock" },
	{ Id = "Celestial", Model = "CelestialRock" },
	{ Id = "Eternal", Model = "EternalRock" },
	{ Id = "Cosmic", Model = "CosmicRock" },
	{ Id = "Ascendant", Model = "AscendantRock" },
}

local OreConfig = {}

OreConfig.PIECES_PER_ROCK = PIECES_PER_ROCK

-- Порядок руд (как в List) — для UI/сортировок.
OreConfig.Order = {} :: { string }

local byId: { [string]: Ore } = {}

for index, entry in ipairs(List) do
	byId[entry.Id] = {
		Id = entry.Id,
		Model = entry.Model,
		MaxHp = entry.MaxHp or math.floor(BASE_HP * RATIO ^ (index - 1) + 0.5),
		PieceWeight = entry.PieceWeight or DEFAULT_PIECE_WEIGHT,
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
