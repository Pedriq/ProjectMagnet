local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local MagnetShopPanel = require(ReplicatedStorage.ClientSource.UI.screens.MagnetShopPanel)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local create = Vide.create

-- В UI Labs Knit не стартует -> Data.start() не зовём, значения подкидываем руками.
local story = {
	vide = Vide,
	story = function()
		Data.money("5e11") -- хватает до Saber включительно, дальше кнопка Money гаснет
		Data.magnet({ Name = "SwordSaw", Magnetism = 267000 }) -- надет Sword Saw
		Data.ownedMagnets({ Stick = true, Cleaver = true, Katana = true, SwordSaw = true })

		return create("Frame")({
			Size = UDim2.fromOffset(720, 640),
			BackgroundColor3 = Color3.fromRGB(60, 66, 110),
			BackgroundTransparency = 0,

			MagnetShopPanel({
				OnClose = function()
					print("close Cutters")
				end,
				OnBuyMoney = function(name)
					print("buy money ->", name)
				end,
				OnBuyRobux = function(name)
					print("buy robux ->", name)
				end,
				OnEquip = function(name)
					print("equip ->", name)
					Data.magnet({ Name = name })
				end,
			})(),
		})
	end,
}

return story
