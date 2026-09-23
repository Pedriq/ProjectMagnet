local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local ShopPanel = require(ReplicatedStorage.ClientSource.UI.screens.ShopPanel)

return {
	vide = Vide,
	story = function()
		local open = Vide.source(true)
		return Vide.create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(65, 60, 80),
			Vide.show(open, ShopPanel({
				OnClose = function()
					open(false)
				end,
			})),
		})
	end,
}
