local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local HUD = require(ReplicatedStorage.ClientSource.UI.screens.HUD)
local ClickEffect = require(ReplicatedStorage.ClientSource.UI.components.ClickEffect)

local create = vide.create

-- Оборачивает экран-Frame в собственный ScreenGui.
local function Screen(name: string, content: () -> Instance, displayOrder: number?)
	return create("ScreenGui")({
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,

		content(),
	})
end

-- Корень интерфейса: папка под PlayerGui со всеми экранами.
local function App()
	return create("Folder")({
		Name = "UI",

		Screen("HUD", HUD, 1),
		Screen("ClickEffect", ClickEffect, 5),
	})
end

return App
