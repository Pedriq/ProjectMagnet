local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local vide = require(ReplicatedStorage.Packages.Vide)

local Data = require(ReplicatedStorage.ClientSource.UI.data)

--[[
	CheckpointController — локальный визуал чекпоинтов (см. CheckpointHandler).
	Пройденный чекпоинт становится полностью прозрачным только у этого игрока,
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

---- State
local originalTransparency = {} -- [BasePart] = Transparency до прохода
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

function CheckpointController:Hide(part: BasePart)
	if originalTransparency[part] == nil then
		originalTransparency[part] = part.Transparency
	end
	part.Transparency = 1
end

function CheckpointController:RestoreAll()
	for part, transparency in pairs(originalTransparency) do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(originalTransparency)
end

function CheckpointController:KnitStart()
	PlayerManagerService.CheckpointPassed:Connect(function(part)
		if typeof(part) == "Instance" and part:IsA("BasePart") then
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
