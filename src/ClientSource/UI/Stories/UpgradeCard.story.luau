local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local UpgradeCard = require(ReplicatedStorage.ClientSource.UI.components.UpgradeCard)

local create = Vide.create
local source = Vide.source

local story = {
	vide = Vide,
	story = function()
		local level = source(32)

		return create("Frame")({
			Size = UDim2.fromOffset(540, 120),
			BackgroundColor3 = Color3.fromRGB(16, 34, 20),

			UpgradeCard({
				Title = "Range",
				Bonus = "+7.5% Atk. Radius",
				Icon = "",

				Level = level,
				CostText = function()
					return "$21.9Qa"
				end,
				RobuxText = function()
					return "R$ 139"
				end,

				MoneyDisabled = function()
					return false
				end,
				OnBuyMoney = function()
					level(level() + 1)
					print("buy money -> Range", level())
				end,
				OnBuyRobux = function()
					print("buy robux -> Range")
				end,
			}),
		})
	end,
}

return story
