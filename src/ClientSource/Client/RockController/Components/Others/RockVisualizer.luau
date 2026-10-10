local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local perf = require(ReplicatedStorage.ClientSource.perf)
local Knit = require(ReplicatedStorage.Packages.Knit)
local RockGeometry = require(ReplicatedStorage.SharedSource.Object.RockGeometry)
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

	local ore = OreConfig.Get(section)
	local rockTemplate = ore and rockTemplates:FindFirstChild(ore.Model)

	if not rockTemplate then
		warn("Rock template not found:", section)
		return
	end

	local rockClone = rockTemplate:Clone()

	-- Визуальная модель — только картинка: блокирует игрока серверный хитбокс
	-- (rock). Иначе модель коллайдилась бы сверх хитбокса, а после разрушения её
	-- «скорлупа» (VisualEffects:ShatterRock держит её SHATTER_MODEL_CLEANUP сек)
	-- ещё мешала бы бежать. Один раз при создании — и физике меньше работы:
	-- модель двигают тряска/дрожание (PivotTo), без коллизий это дешевле.
	for _, part in ipairs(rockClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end

	-- Ставим геометрический низ модели (а не её pivot, который у камня
	-- смещён от низа) на нижнюю грань hitbox.
	local pivotToBottom = RockGeometry.GetMetrics(section).pivotToBottom
	local spawnCFrame = rock.CFrame * CFrame.new(0, -rock.Size.Y / 2 + pivotToBottom, 0)

	rockClone:PivotTo(spawnCFrame)
	-- «Покойное» положение камня: от него считают и тряску удара (VisualEffects),
	-- и магнитное дрожание (MagnetWobble) — обе анимации пишут абсолютный pivot,
	-- поэтому камень никогда не «уползает». BaseBottom — точка у основания, вокруг
	-- которой камень наклоняется к магниту.
	rockClone:SetAttribute("BasePivot", spawnCFrame)
	rockClone:SetAttribute("BaseBottom", (spawnCFrame * CFrame.new(0, -pivotToBottom, 0)).Position)
	rockClone.Parent = workspace

	local visualData = {
		Model = rockClone,
		BrokenSegments = 0,
		-- для HitFeedback: цвет руды и сколько HP было до удара (цифра урона)
		Section = section,
		Hp = rock:GetAttribute("Hp"),
		-- серверный хитбокс камня — RockController снимает с него коллизию
		-- локально в момент добивающего удара (см. HitRock)
		Hitbox = rock,
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

	-- Та же формула, по которой сервер начисляет руду за отколотые кусочки.
	local targetBroken = OreConfig.PiecesBroken(hp, maxHp)

	if targetBroken <= visualData.BrokenSegments then
		return
	end

	for segmentIndex = OreConfig.PIECES_PER_ROCK, 1, -1 do
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

-- Целая полоса камней приходит разом: клон модели + проход по всем деталям на каждый
-- камень в один кадр давали лаг-спайк при беге на высокой скорости. На мобильных
-- визуалы создаются очередью (perf.rockVisualsPerFrame за кадр), на ПК — сразу, как раньше.
local pending: { BasePart } = {}
local pendingHead = 1

local function enqueueVisual(descendant: Instance)
	if perf.rockVisualsPerFrame == math.huge then
		RockVisualizer:CreateRockVisual(descendant)
	elseif descendant:IsA("BasePart") then
		table.insert(pending, descendant)
	end
end

local function drainQueue()
	local budget = perf.rockVisualsPerFrame
	while budget > 0 and pendingHead <= #pending do
		local rock = pending[pendingHead]
		pending[pendingHead] = nil
		pendingHead += 1
		-- камень мог исчезнуть (деспавн полосы/добит), пока ждал очереди
		if rock.Parent then
			RockVisualizer:CreateRockVisual(rock)
			budget -= 1
		end
	end
	if pendingHead > #pending then
		table.clear(pending)
		pendingHead = 1
	end
end

function RockVisualizer.Start()
	PlayerRockFolder.DescendantAdded:Connect(enqueueVisual)

	PlayerRockFolder.DescendantRemoving:Connect(function(descendant)
		RockVisualizer:DeleteRockVisual(descendant)
	end)

	for _, descendant in ipairs(PlayerRockFolder:GetDescendants()) do
		enqueueVisual(descendant)
	end

	if perf.rockVisualsPerFrame ~= math.huge then
		RunService.Heartbeat:Connect(drainQueue)
	end
end

function RockVisualizer.Init()
	RockController = Knit.GetController("RockController")
end

return RockVisualizer
