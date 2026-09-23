local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local RockGeometry = require(ReplicatedStorage.SharedSource.Objects.RockGeometry)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)

local RockVisualizer = {}

local player = Players.LocalPlayer

local PlayersRockFolder = workspace:WaitForChild("PlayersRock")

-- См. RockController/init.luau — тот же риск молчаливого зависания bootstrap'а,
-- та же защита таймаутом с предупреждением.
local rockFolderName = tostring(player.UserId) .. "_Rock"
local PlayerRockFolder = PlayersRockFolder:FindFirstChild(rockFolderName)
while not PlayerRockFolder do
	warn("RockVisualizer: жду Workspace.PlayersRock." .. rockFolderName .. " от сервера...")
	PlayerRockFolder = PlayersRockFolder:WaitForChild(rockFolderName, 10)
end

local rockTemplates = ReplicatedStorage.Assets.Rock

local RockController

function RockVisualizer:CreateRockVisual(rock)
	if not rock:IsA("BasePart") then
		return
	end

	local stripId = rock:GetAttribute("StripId")
	local rockIndex = rock:GetAttribute("RockIndex")
	local section = rock:GetAttribute("Section")

	if not stripId or not rockIndex or not section then
		return
	end

	local rockKey = tostring(stripId) .. "_" .. tostring(rockIndex)

	if RockController.VisualizedRocks[rockKey] then
		return
	end

	local rockTemplate = rockTemplates:FindFirstChild(tostring(section) .. "Rock")

	if not rockTemplate then
		warn("Rock template not found:", section)
		return
	end

	local rockClone = rockTemplate:Clone()

	-- Ставим геометрический низ модели (а не её pivot, который у камня
	-- смещён от низа) на нижнюю грань hitbox.
	local pivotToBottom = RockGeometry.GetMetrics(section).pivotToBottom
	local spawnCFrame = rock.CFrame * CFrame.new(0, -rock.Size.Y / 2 + pivotToBottom, 0)

	rockClone:PivotTo(spawnCFrame)
	rockClone.Parent = workspace

	local visualData = {
		Model = rockClone,
		BrokenSegments = 0,
	}

	RockController.VisualizedRocks[rockKey] = visualData

	-- Синхронизируем повреждение без анимации
	self:UpdateRockDamage(rock:GetAttribute("Hp"), rock:GetAttribute("MaxHp"), visualData, false)
end

function RockVisualizer:DeleteRockVisual(rock)
	if not rock:IsA("BasePart") then
		return
	end

	local stripId = rock:GetAttribute("StripId")
	local rockIndex = rock:GetAttribute("RockIndex")

	if not stripId or not rockIndex then
		return
	end

	local rockKey = tostring(stripId) .. "_" .. tostring(rockIndex)

	local visualData = RockController.VisualizedRocks[rockKey]

	if not visualData then
		return
	end

	RockController.VisualizedRocks[rockKey] = nil

	if not visualData.Model then
		return
	end

	-- Cut выставляется сервером только на смертельном ударе (ApplyDamage). Тогда
	-- проигрываем импакт-развал; при любом другом удалении (деспавн полосы, выход
	-- игрока, переиспользование пула) просто убираем модель.
	if rock:GetAttribute("Cut") then
		RockController.Components.VisualEffects:ShatterRock(visualData.Model)
	else
		visualData.Model:Destroy()
	end
end

function RockVisualizer:UpdateRockDamage(hp, maxHp, visualData, animate)
	if not hp or not maxHp or maxHp <= 0 then
		warn("Not rock hp")
		return
	end

	local MAX_SEGMENTS = OreConfig.SEGMENTS_PER_ROCK

	-- Та же формула, по которой сервер начисляет кусочки руды.
	local targetBroken = OreConfig.GetBrokenSegments(hp, maxHp)

	if targetBroken <= visualData.BrokenSegments then
		return
	end

	for segmentIndex = MAX_SEGMENTS, 1, -1 do
		if visualData.BrokenSegments >= targetBroken then
			break
		end

		local segment = visualData.Model:FindFirstChild(tostring(segmentIndex))

		if segment then
			if animate then
				RockController:BreakSegment(segment)
			else
				segment:Destroy()
			end

			visualData.BrokenSegments += 1
		end
	end
end

function RockVisualizer.Start()
	PlayerRockFolder.DescendantAdded:Connect(function(descendant)
		RockVisualizer:CreateRockVisual(descendant)
	end)

	PlayerRockFolder.DescendantRemoving:Connect(function(descendant)
		RockVisualizer:DeleteRockVisual(descendant)
	end)

	for _, descendant in ipairs(PlayerRockFolder:GetDescendants()) do
		RockVisualizer:CreateRockVisual(descendant)
	end
end

function RockVisualizer.Init()
	RockController = Knit.GetController("RockController")
end

return RockVisualizer
