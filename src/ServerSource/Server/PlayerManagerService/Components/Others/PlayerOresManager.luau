local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PlayerOresManager = {}

---- Knit Services
local PlayerManagerService

---- Разгрузка на прессе
-- Как часто снимаем кусочки, пока игрок стоит на SellPart, и сколько за раз.
local UNLOAD_TICK = 0.08
local UNLOAD_PIECES_PER_TICK = 1
-- Насколько выше верхней грани SellPart ещё считаем, что игрок «стоит» на нём
-- (HumanoidRootPart висит ~3 стада над полом).
local SELL_PART_HEIGHT_TOLERANCE = 6

-- [player] = true — синк Ores в профиль уже запланирован на конец кадра.
local pendingSync = {}

--[[
	Шлём Ores клиенту (ProfileService.ChangeData → UpdateSpecificData) не на
	каждое изменение, а раз в кадр: большой хитбокс ломает десятки камней за
	удар, и каждый дал бы отдельный remote.
]]
local function scheduleSync(player)
	if pendingSync[player] then
		return
	end
	pendingSync[player] = true

	task.defer(function()
		pendingSync[player] = nil
		if not player:IsDescendantOf(Players) then
			return
		end

		local ores = PlayerManagerService:GetPlayerOres(player)
		if not ores then
			return
		end

		PlayerManagerService:ChangePlayerOres(player, ores)
		-- Для отладки: видно в Properties игрока.
		player:SetAttribute("OresTotalWeight", ores.TotalWeight)
	end)
end

function PlayerOresManager:AddOrePieces(player, oreName: string, pieces: number)
	if pieces <= 0 then
		return
	end

	local ores = PlayerManagerService:GetPlayerOres(player)
	if not ores then
		return
	end

	local weight = pieces * OreConfig.GetPieceWeight(oreName)

	local ore = ores.Items[oreName]
	if not ore then
		ore = { Weight = 0, Pieces = 0 }
		ores.Items[oreName] = ore
	end

	ore.Pieces += pieces
	ore.Weight += weight
	ores.TotalWeight += weight

	scheduleSync(player)
end

-- Снимает один кусочек любой руды из инвентаря. Возвращает имя руды или nil, если пусто.
function PlayerOresManager:RemoveOnePiece(player): string?
	local ores = PlayerManagerService:GetPlayerOres(player)
	if not ores then
		return nil
	end

	for oreName, ore in pairs(ores.Items) do
		if ore.Pieces > 0 then
			-- Вес кусочка берём как средний по стопке, а не из конфига: если конфиг
			-- весов поменяется, уже добытая руда всё равно разгрузится в ноль.
			local pieceWeight = ore.Weight / ore.Pieces

			ore.Pieces -= 1
			ore.Weight = math.max(ore.Weight - pieceWeight, 0)
			ores.TotalWeight = math.max(ores.TotalWeight - pieceWeight, 0)

			if ore.Pieces <= 0 then
				ores.Items[oreName] = nil
			end

			scheduleSync(player)
			return oreName
		end

		ores.Items[oreName] = nil
	end

	ores.TotalWeight = 0
	return nil
end

local function isStandingOn(player, part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local localPos = part.CFrame:PointToObjectSpace(root.Position)
	local half = part.Size / 2

	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Z) <= half.Z
		and localPos.Y >= -half.Y
		and localPos.Y <= half.Y + SELL_PART_HEIGHT_TOLERANCE
end

-- Пока игрок стоит на SellPart — по кусочку разгружаем его руду в пресс.
-- Ушёл с парта — разгрузка просто перестаёт идти.
local function runUnloadLoop()
	local press = workspace:WaitForChild("HydraulicPress")
	local sellPart = press:WaitForChild("SellPart")

	while true do
		task.wait(UNLOAD_TICK)

		for _, player in ipairs(Players:GetPlayers()) do
			if not isStandingOn(player, sellPart) then
				continue
			end

			for _ = 1, UNLOAD_PIECES_PER_TICK do
				local oreName = PlayerOresManager:RemoveOnePiece(player)
				if not oreName then
					break
				end

				PlayerManagerService.Client.UnloadOrePiece:FireAll(player, oreName)
			end
		end
	end
end

function PlayerOresManager.Start()
	task.spawn(runUnloadLoop)

	Players.PlayerRemoving:Connect(function(player)
		pendingSync[player] = nil
	end)
end

function PlayerOresManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return PlayerOresManager
