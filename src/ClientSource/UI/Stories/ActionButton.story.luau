local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local ActionButton = require(ReplicatedStorage.ClientSource.UI.components.ActionButton)

local create = Vide.create
local source = Vide.source

local story = {
	vide = Vide,
	story = function()
		local count = source(0)

		return create("Frame")({
			Size = UDim2.fromOffset(360, 140),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
			}),

			-- обычная, с реагирующим на клик текстом
			ActionButton({
				Icon = "rbxassetid://1234567890",
				Text = function()
					return "Rebirth " .. count()
				end,
				OnActivated = function()
					count(count() + 1)
				end,
				LayoutOrder = 1,
			}),

			-- цветная
			ActionButton({
				Icon = "rbxassetid://1234567890",
				Text = "Boost",
				Color = Color3.fromRGB(36, 82, 46),
				OnActivated = function()
					print("boost")
				end,
				LayoutOrder = 2,
			}),

			-- disabled
			ActionButton({
				Icon = "rbxassetid://1234567890",
				Text = "Locked",
				Disabled = true,
				LayoutOrder = 3,
			}),
		})
	end,
}

return story
