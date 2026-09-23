local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local XpBar = require(ReplicatedStorage.ClientSource.UI.components.XpBar)

local create = Vide.create
local source = Vide.source
local cleanup = Vide.cleanup

local story = {
	vide = Vide,
	story = function()
		local current = source(120)

		local alive = true
		cleanup(function()
			alive = false
		end)
		task.spawn(function()
			while alive do
				task.wait(1.2)
				current(math.random(0, 500))
			end
		end)

		return create("Frame")({
			Size = UDim2.fromOffset(300, 90),
			BackgroundTransparency = 1,

			XpBar({
				Icon = "", -- сюда rbxassetid бицепса
				Level = 7,
				Current = current,
				Required = 500,
				Total = 15400,
				Large = true,
				-- цвет заливки по умолчанию — оранжево-жёлтый
				TrackImage = "83851547930080",
				FillImage = "83851547930080",
			}),
		})
	end,
}

return story
