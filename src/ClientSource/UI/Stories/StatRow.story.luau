local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatRow = require(ReplicatedStorage.ClientSource.UI.components.StatRow)
local Vide = require(ReplicatedStorage.Packages.Vide)

local story = {
	vide = Vide,
	story = function()
		return StatRow({
			Icon = "rbxassetid://1234567890",
			Text = "$ 3.5k",
			Large = false,
		})
	end,
}

return story
