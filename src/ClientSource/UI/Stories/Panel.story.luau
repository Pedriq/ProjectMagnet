local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local ActionButton = require(ReplicatedStorage.ClientSource.UI.components.ActionButton)

local create = Vide.create

local story = {
	vide = Vide,
	story = function()
		return create("Frame")({
			Size = UDim2.fromOffset(420, 520),
			BackgroundColor3 = Color3.fromRGB(60, 120, 70), -- фон-заглушка, чтобы видеть прозрачность
			BackgroundTransparency = 0,

			Panel({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(360, 460),

				Title = "Shop",
				Icon = "rbxassetid://95100426738981",
				OnClose = function()
					print("close Shop")
				end,

				-- TitleImage = "rbxassetid://...",        -- основная текстура полоски
				-- TitleOverlayImage = "rbxassetid://...", -- блик / стрелка поверх

				-- дети уходят в тело (вертикальный список по умолчанию)
				create("TextLabel")({
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 40),
					BackgroundColor3 = Color3.fromRGB(30, 26, 40),
					BackgroundTransparency = 0.2,
					Font = Enum.Font.GothamBold,
					TextSize = 16,
					TextColor3 = Color3.fromRGB(235, 235, 235),
					Text = "Элемент с обводкой",

					create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					create("UIStroke")({ Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.1 }),
				}),
				ActionButton({
					LayoutOrder = 2,
					Icon = "rbxassetid://95100426738981",
					Text = "Buy",
					OnActivated = function() end,
				}),
			}),
		})
	end,
}

return story
