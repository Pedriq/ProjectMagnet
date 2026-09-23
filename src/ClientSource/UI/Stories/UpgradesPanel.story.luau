local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local UpgradesPanel = require(ReplicatedStorage.ClientSource.UI.screens.UpgradesPanel)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local create = Vide.create

-- В UI Labs Knit не стартует -> Data.start() не зовём, значения подкидываем руками.
local story = {
	vide = Vide,
	story = function()
		Data.money("50000")
		-- Range/Agility — по карману; Capacity — дорого (кнопка Money гаснет);
		-- Mobility на MaxLevel (100) -> кнопка Money = "MAX" и заблокирована.
		Data.upgradeLevels({ Range = 32, Agility = 8, Capacity = 60, Mobility = 100 })

		return create("Frame")({
			Size = UDim2.fromOffset(660, 620),
			BackgroundColor3 = Color3.fromRGB(70, 118, 72), -- фон-заглушка под прозрачность тела
			BackgroundTransparency = 0,

			UpgradesPanel({
				OnClose = function()
					print("close Upgrades")
				end,
				OnBuyMoney = function(statKey)
					print("buy with money ->", statKey)
				end,
				OnBuyRobux = function(statKey)
					print("buy with robux ->", statKey)
				end,
			})(),
		})
	end,
}

return story
