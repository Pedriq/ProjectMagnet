local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local HUD = require(ReplicatedStorage.ClientSource.UI.screens.HUD)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local cleanup = Vide.cleanup

-- В UI Labs Knit не стартует, поэтому Data.start() не вызывается —
-- подкидываем данные вручную, чтобы видеть разметку и анимацию.
local story = {
	vide = Vide,
	story = function()
		Data.level(4)
		Data.money("125000")
		Data.rebirths(7)
		Data.carryCount(2)
		Data.carryCapacity(5)

		local alive = true
		cleanup(function()
			alive = false
		end)
		task.spawn(function()
			while alive do
				Data.strength(tostring(math.random(0, 900)))
				task.wait(1.2)
			end
		end)

		return HUD()
	end,
}

return story
