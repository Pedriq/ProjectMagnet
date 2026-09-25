local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

--[[
	CheckpointController — локальный визуал чекпоинтов (см. CheckpointHandler).
	Пройденный чекпоинт становится полностью прозрачным только у этого игрока,
	на ресет (Entrance -> Save) возвращается стартовая прозрачность.
]]
local CheckpointController = Knit.CreateController({
	Name = "CheckpointController",
})

--- Knit Services
local PlayerManagerService

---- State
local originalTransparency = {} -- [BasePart] = Transparency до прохода

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
		end
	end)

	PlayerManagerService.CheckpointsReset:Connect(function()
		self:RestoreAll()
	end)
end

function CheckpointController:KnitInit()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return CheckpointController
