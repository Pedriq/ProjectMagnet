local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local RebirthPanel = require(ReplicatedStorage.ClientSource.UI.screens.RebirthPanel)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local create = Vide.create

-- В UI Labs Knit не стартует -> Data.start() не зовём, подкидываем значения руками.
local story = {
	vide = Vide,
	story = function()
		Data.rebirths(15)
		Data.level(7) -- < RequiredLevelForRebirth(15) -> кнопка Rebirth заблокирована

		return create("Frame")({
			Size = UDim2.fromOffset(620, 560),
			BackgroundColor3 = Color3.fromRGB(60, 120, 70), -- фон-заглушка под прозрачность
			BackgroundTransparency = 0,

			RebirthPanel({
				OnClose = function()
					print("close Rebirth")
				end,
				OnRebirth = function()
					print("rebirth")
				end,
				OnSkip = function()
					print("skip")
				end,
			})(),
		})
	end,
}

return story
