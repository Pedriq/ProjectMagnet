local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local SellPanel = require(ReplicatedStorage.ClientSource.UI.screens.SellPanel)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local create = Vide.create

-- В UI Labs Knit не стартует -> Data.start() не зовём, значения подкидываем руками.
local story = {
	vide = Vide,
	story = function()
		Data.cashMultiplier(2) -- x2 за ребёрсы — цены в панели уже с ним

		-- склад: map[guid] = { Name, Price, Rarity }; две "Spirit Feather" -> стопка x2
		Data.items({
			["a1"] = { Name = "Spirit Feather", Price = 121000000000, Rarity = "Rare" },
			["a2"] = { Name = "Spirit Feather", Price = 121000000000, Rarity = "Rare" },
			["b1"] = { Name = "Fate Dice", Price = 214000000000, Rarity = "Epic" },
			["c1"] = { Name = "Celestial Antler", Price = 4400000000, Rarity = "Celestial" },
			["d1"] = { Name = "Void Crystal", Price = 850000, Rarity = "Secret" },
		})

		return create("Frame")({
			Size = UDim2.fromOffset(660, 640),
			BackgroundColor3 = Color3.fromRGB(70, 118, 72),
			BackgroundTransparency = 0,

			SellPanel({
				OnClose = function()
					print("close Sell Loot")
				end,
				OnSellItem = function(ids)
					print("sell stack:", table.concat(ids, ", "))
				end,
				OnSellAll = function()
					print("sell all")
				end,
				OnSellX2 = function()
					print("sell x2")
				end,
				OnLock = function(name)
					print("lock:", name)
				end,
			})(),
		})
	end,
}

return story
