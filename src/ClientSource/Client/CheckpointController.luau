local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Knit = require(ReplicatedStorage.Packages.Knit)
local vide = require(ReplicatedStorage.Packages.Vide)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local juice = require(ReplicatedStorage.ClientSource.juice)
local sfx = require(ReplicatedStorage.ClientSource.sfx)

--[[
	CheckpointController — локальный визуал чекпоинтов (см. CheckpointHandler).
	Проход: мягкая подсветка ворот, волна, искры, «+N ORE SAVED», звук (playPassEffect),
	затем чекпоинт плавно становится прозрачным только у этого игрока,
	на ресет (Entrance -> Save) возвращается стартовая прозрачность.

	Подсказка «Enter to Save Ore» (SurfaceGui в чекпоинте) видна только на
	СЛЕДУЮЩЕМ чекпоинте: порядок — по имени прямого ребёнка Workspace.Checkpoints
	(«1», «2», «3»… или «Checkpoint3»; парт или модель с партом). Следующий — с
	наименьшим номером больше самого дальнего пройденного. Текст ставится
	кодом: «Checkpoint: Enter to Save N Ore», N — руда в переноске (Data.carryCount).
]]
local CheckpointController = Knit.CreateController({
	Name = "CheckpointController",
})

--- Knit Services
local PlayerManagerService

---- Datas
local FOLDER_NAME = "Checkpoints"
local PASS_COLOR = Theme.Money -- чекпоинт активирован: «успех» (язык цвета UI.theme)
local ORE_COLOR = Theme.CopperBright -- руда, как в CarryMeter
-- Интенсивность эффекта прохода (больше прозрачность / меньше tint — тише)
local GATE_TINT = 0.45 -- насколько ворота окрашиваются в PASS_COLOR (0..1)
local GATE_GLOW_TRANSPARENCY = 0.55 -- до какой прозрачности ворота «проявляются»
local WAVE_TRANSPARENCY = 0.7 -- стартовая прозрачность волны

---- State
local originalTransparency = {} -- [BasePart] = Transparency до прохода
local hideTweens: { [BasePart]: Tween } = {} -- плавное исчезновение после вспышки
local folder: Instance? = nil
local highestPassed = 0 -- номер самого дальнего пройденного чекпоинта (0 — ни одного)

-- Число в имени: «3», «Checkpoint3», «Checkpoint 3».
local function numberIn(name: string): number?
	return tonumber(name) or tonumber(string.match(name, "%d+"))
end

-- Номер чекпоинта, к которому относится inst: первое число в именах по пути
-- от папки Checkpoints вниз к inst (модель «3» > парт «Checkpoint» и парт «3»).
local function indexOf(inst: Instance?): number?
	if not folder or not inst or not inst:IsDescendantOf(folder) then
		return nil
	end
	local chain = {}
	local current: Instance? = inst
	while current and current ~= folder do
		if current:IsA("BasePart") or current:IsA("Model") or current:IsA("Folder") then
			table.insert(chain, 1, current)
		end
		current = current.Parent
	end
	for _, node in ipairs(chain) do
		local n = numberIn(node.Name)
		if n then
			return n
		end
	end
	return nil
end

-- Все SurfaceGui чекпоинтов: внутри папки и в PlayerGui с Adornee на чекпоинт.
local function collectGuis(): { [SurfaceGui]: number }
	local result = {}
	if not folder then
		return result
	end
	for _, gui in ipairs(folder:GetDescendants()) do
		if gui:IsA("SurfaceGui") then
			local index = indexOf(gui.Adornee or gui.Parent)
			if index then
				result[gui] = index
			end
		end
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, gui in ipairs(playerGui:GetDescendants()) do
			if gui:IsA("SurfaceGui") and gui.Adornee then
				local index = indexOf(gui.Adornee)
				if index then
					result[gui] = index
				end
			end
		end
	end
	return result
end

-- Номер следующего чекпоинта: наименьший номер > highestPassed.
local function nextIndex(guis: { [SurfaceGui]: number }): number?
	local best: number? = nil
	for _, index in pairs(guis) do
		if index > highestPassed and (best == nil or index < best) then
			best = index
		end
	end
	return best
end

-- Текст подсказки: сколько руды сейчас несёт игрок.
local function promptText(): string
	return `Checkpoint: Enter to Save {Data.carryCount()} Ore`
end

-- Включает SurfaceGui только у следующего чекпоинта и обновляет количество руды.
local function refresh()
	if not folder then
		return
	end
	local guis = collectGuis()
	local target = nextIndex(guis)
	local text = promptText()
	for gui, index in pairs(guis) do
		local active = index == target
		gui.Enabled = active
		if active then
			for _, label in ipairs(gui:GetDescendants()) do
				if label:IsA("TextLabel") or label:IsA("TextButton") then
					label.Text = text
				end
			end
		end
	end
end

-- Ворота мягко подсвечиваются и плавно гаснут (вместо мгновенного Transparency = 1).
function CheckpointController:Hide(part: BasePart)
	if originalTransparency[part] == nil then
		originalTransparency[part] = part.Transparency
	end
	local previous = hideTweens[part]
	if previous then
		previous:Cancel()
	end
	part.Transparency = math.min(part.Transparency, GATE_GLOW_TRANSPARENCY)
	local tween = TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.1), {
		Transparency = 1,
	})
	hideTweens[part] = tween
	tween:Play()
end

function CheckpointController:RestoreAll()
	for _, tween in pairs(hideTweens) do
		tween:Cancel()
	end
	table.clear(hideTweens)
	for part, transparency in pairs(originalTransparency) do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(originalTransparency)
end

-- Тихая расходящаяся «волна» в форме ворот: полупрозрачная копия-коробка
-- (не неон) чуть растёт и тает. Чисто визуально, локально, без коллизий/запросов.
local function shockwave(part: BasePart, growth: number)
	local wave = Instance.new("Part")
	wave.Name = "CheckpointWave"
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Material = Enum.Material.ForceField
	wave.Color = PASS_COLOR
	wave.Transparency = WAVE_TRANSPARENCY
	wave.Size = part.Size
	wave.CFrame = part.CFrame
	wave.Parent = workspace

	TweenService:Create(wave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = part.Size * growth,
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.55)
end

-- Эффект прохода чекпоинта (сдержанный): лёгкая подсветка ворот, одна мягкая
-- волна, немного искр, «+N ORE SAVED» и тихий звук. Без тряски камеры.
local function playPassEffect(part: BasePart, saved: number)
	local originalColor = part.Color
	part.Color = originalColor:Lerp(PASS_COLOR, GATE_TINT)
	task.delay(0.6, function()
		if part.Parent then
			part.Color = originalColor -- к ресету ворота вернутся в своём цвете
		end
	end)

	shockwave(part, 1.25)

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = root and root.Position or part.Position
	juice.burst(origin, PASS_COLOR, 10, { speed = 0.6, size = 0.6 })

	local text = if saved > 0 then `+{saved} ORE SAVED` else "CHECKPOINT"
	juice.worldText(origin + Vector3.new(0, 3, 0), text, if saved > 0 then ORE_COLOR else PASS_COLOR, {
		size = 0.9,
		rise = 1.5,
		time = 1,
		scatter = 0,
	})

	sfx.play("Checkpoint")
end

function CheckpointController:KnitStart()
	PlayerManagerService.CheckpointPassed:Connect(function(part, saved)
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			playPassEffect(part, tonumber(saved) or 0)
			self:Hide(part)
			local index = indexOf(part)
			if index and index > highestPassed then
				highestPassed = index
			end
			refresh()
		end
	end)

	PlayerManagerService.CheckpointsReset:Connect(function()
		self:RestoreAll()
		highestPassed = 0
		refresh()
	end)

	task.spawn(function()
		folder = workspace:WaitForChild(FOLDER_NAME, 30)
		if not folder then
			warn("[CheckpointController] не найден Workspace." .. FOLDER_NAME)
			return
		end
		-- новые/подгруженные стримингом чекпоинты сразу получают верное состояние
		folder.DescendantAdded:Connect(function(inst)
			if inst:IsA("SurfaceGui") or inst:IsA("TextLabel") or inst:IsA("TextButton") then
				task.defer(refresh)
			end
		end)
		-- SurfaceGui могут жить и в PlayerGui с Adornee на чекпоинт
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		playerGui.DescendantAdded:Connect(function(inst)
			if inst:IsA("SurfaceGui") then
				task.defer(refresh)
			end
		end)

		-- количество руды на подсказке — реактивно от инвентаря переноски
		vide.root(function()
			vide.effect(function()
				Data.carryCount()
				vide.untrack(refresh)
			end)
		end)
	end)
end

function CheckpointController:KnitInit()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return CheckpointController
