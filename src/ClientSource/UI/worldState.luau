local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local vide = require(ReplicatedStorage.Packages.Vide)

local source = vide.source

--[[
	WorldState — реактивное состояние «где игрок относительно базы» для HUD.

	Поля — Vide-источники:
	  passedEntrance — прошёл ли игрок сквозь парт с тегом "Entrance"
	                   (ушёл на вылазку). Сбрасывается в false при входе в
	                   SaveItemsZone — чтобы кнопка Base не появлялась при
	                   каждом выходе из сейв-зоны, а только если игрок заново
	                   прошёл через Entrance.
	  inSaveZone     — стоит ли HRP игрока внутри парта с тегом "SaveItemsZone".

	Правило показа (showXpBar):
	  в SaveItemsZone           -> XpBar
	  иначе, если прошёл вход    -> кнопка Base
	  иначе (ещё не выходил)     -> XpBar

	Инициализация: WorldState.start() из InitPlayerUI после Data.start().
]]
local WorldState = {}

-- Парт-вход: пройти сквозь него -> игрок «на вылазке».
local ENTRANCE_TAG = "Entrance"
-- Парты сейв-зон.
local ZONE_TAG = "SaveItemsZone"
-- Как часто проверять присутствие в сейв-зоне.
local CHECK_INTERVAL = 0.3

WorldState.passedEntrance = source(false)
WorldState.inSaveZone = source(false)

-- true -> показывать XpBar, false -> показывать кнопку Base.
function WorldState.showXpBar(): boolean
	return WorldState.inSaveZone() or not WorldState.passedEntrance()
end

local started = false

function WorldState.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer

	--== Entrance: проход сквозь -> флаг «на вылазке» ==
	local function bindEntrance(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		part.Touched:Connect(function(hit)
			local character = player.Character
			if character and hit:IsDescendantOf(character) then
				WorldState.passedEntrance(true)
			end
		end)
	end

	for _, part in ipairs(CollectionService:GetTagged(ENTRANCE_TAG)) do
		bindEntrance(part)
	end
	CollectionService:GetInstanceAddedSignal(ENTRANCE_TAG):Connect(bindEntrance)

	--== SaveItemsZone: опрос присутствия локального HRP ==
	task.spawn(function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.MaxParts = 1

		while true do
			task.wait(CHECK_INTERVAL)

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			local inside = false
			if root then
				params.FilterDescendantsInstances = { root }
				for _, zone in ipairs(CollectionService:GetTagged(ZONE_TAG)) do
					if zone:IsA("BasePart") and #workspace:GetPartsInPart(zone, params) > 0 then
						inside = true
						break
					end
				end
			end

			if inside ~= WorldState.inSaveZone() then
				WorldState.inSaveZone(inside)
				if inside then
					WorldState.passedEntrance(false)
				end
			end
		end
	end)
end

return WorldState
