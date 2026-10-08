local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local HUD = require(ReplicatedStorage.ClientSource.UI.screens.HUD)
local ClickEffect = require(ReplicatedStorage.ClientSource.UI.components.ClickEffect)
local FeedbackOverlay = require(ReplicatedStorage.ClientSource.UI.components.FeedbackOverlay)
local TutorialOverlay = require(ReplicatedStorage.ClientSource.UI.components.TutorialOverlay)

local OfflineRewardsPanel = require(ReplicatedStorage.ClientSource.UI.screens.OfflineRewardsPanel)

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
		-- баннеры, комбо, BAG FULL, цель «следующий магнит», вспышки.
		-- Ниже HUD: открытые панели (магазин и т.п.) всегда перекрывают этот слой.
		Screen("Feedback", FeedbackOverlay, 0),
		-- плашка-цель и подсказка клика обучения (см. UI/tutorial); ничего не перехватывает.
		-- Ниже HUD: HUD и открытые панели всегда поверх туториала, а не наоборот.
		Screen("Tutorial", TutorialOverlay, 0),
		-- «Welcome Back!» — офлайн-награда при заходе (UI/offline); поверх HUD, под экраном загрузки.
		Screen("OfflineRewards", OfflineRewardsPanel, 8),
	})
end

return App
