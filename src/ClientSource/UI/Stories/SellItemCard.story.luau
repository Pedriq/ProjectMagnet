local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local SellItemCard = require(ReplicatedStorage.ClientSource.UI.components.SellItemCard)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = Vide.create

local story = {
	vide = Vide,
	story = function()
		return create("Frame")({
			Size = UDim2.fromOffset(540, 230),
			BackgroundColor3 = Color3.fromRGB(16, 34, 20),

			create("UIListLayout")({ Padding = UDim.new(0, 10) }),

			SellItemCard({
				LayoutOrder = 1,
				Name = "Spirit Feather",
				Count = 2,
				NameColor = RarityColors.get("Rare"),
				PriceText = function()
					return "+$242T"
				end,
				OnSell = function()
					print("sell Spirit Feather")
				end,
				OnLock = function()
					print("lock Spirit Feather")
				end,
			}),
			SellItemCard({
				LayoutOrder = 2,
				Name = "Celestial Antler",
				Count = 1,
				NameColor = RarityColors.get("Celestial"),
				PriceText = function()
					return "+$8.8T"
				end,
				OnSell = function()
					print("sell Celestial Antler")
				end,
				OnLock = function()
					print("lock Celestial Antler")
				end,
			}),
		})
	end,
}

return story
