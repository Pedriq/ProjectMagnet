local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local UpgradeCard = require(ReplicatedStorage.ClientSource.UI.components.UpgradeCard)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create

--[[
	PressUpgradePanel — окно прокачки пресса (открывается ProximityPrompt'ом у NPC
	постройки PressUpgrade на базе мира, см. UI.baseStructures).

	  ┌─ Press Upgrade ─────────────────────────────── [X] ┐
	  │  [icon] Press Speed  Lv.5   0.50/s → 0.52/s  [$..]  │
	  └─────────────────────────────────────────────────────┘

	Пока в окне одна карточка — скорость крафта (profile.Press.CraftSpeed). Тот же
	UpgradeCard, что в окне Upgrades; цена — общая формула статов
	(StatUpgradesConfig.CostFor("PressSpeed", уровень)), покупку считает сервер
	(PressService:BuySpeedUpgrade). Уровень растёт и после
	CRAFT_MAX_EFFECTIVE_LEVEL, но скорость там уже на потолке
	(см. PressConfig.GetCraftItemsPerSecond).

	Использование:
	  PressUpgradePanel({ OnClose = fn, OnUpgradeSpeed = fn })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnUpgradeSpeed: () -> (),
}

local function formatSpeed(itemsPerSecond: number): string
	-- 2 знака: ранние уровни дают ~+0.02 предм./сек, с одним знаком «0.5 → 0.5»
	return string.format("%.2f/s", itemsPerSecond)
end

local function SpeedUpgradeCard(onUpgrade: () -> ())
	local cfg = StatUpgradesConfig.Stats.PressSpeed

	local function level()
		return Data.pressSpeedLevel()
	end
	local function cost()
		return StatUpgradesConfig.CostFor("PressSpeed", level())
	end
	local function atMax()
		return level() >= cfg.MaxLevel
	end

	return UpgradeCard({
		LayoutOrder = 1,
		Title = cfg.Title,
		Icon = cfg.Icon,
		Level = level,
		-- «0.5/s → 0.5/s»: текущая скорость и после покупки. На потолке — просто 5.0/s.
		Bonus = function()
			local now = PressConfig.GetCraftItemsPerSecond(level())
			local after = PressConfig.GetCraftItemsPerSecond(level() + 1)
			if after <= now then
				return formatSpeed(now) .. " items"
			end
			return formatSpeed(now) .. " → " .. formatSpeed(after)
		end,
		CostText = function()
			return if atMax() then "MAX" else "$" .. Format.short(cost())
		end,
		HideRobux = true,
		MoneyDisabled = function()
			return atMax() or EtNum.me(cost(), Data.money())
		end,
		OnBuyMoney = onUpgrade,
	})
end

local function PressUpgradePanel(props: Props)
	return function()
		return Panel({
			ZIndex = 10,
			Size = UDim2.fromOffset(560, 520),
			OnClose = props.OnClose,

			Title = "Press Upgrade",
			-- пресс = медь/ржавчина (UI.theme), как окно Press Queue
			TitleColor = Theme.titleColor("Copper"),
			BodyColor = Theme.bodyColor("Copper"),
			BodyTransparency = Theme.PanelBodyTransparency,
			StrokeColor = Theme.Outline,
			TitleImage = Theme.PanelTitleTexture,
			TitleImageTransparency = Theme.PanelTitleTextureTransparency,
			StrokeThickness = Theme.PanelStrokeThickness,

			List = false,

			create("ScrollingFrame")({
				Name = "List",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0),
				ScrollBarImageTransparency = 0.4,
				VerticalScrollBarInset = Enum.ScrollBarInset.Always,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 10),
				}),
				create("UIPadding")({
					PaddingTop = UDim.new(0, 2),
					PaddingBottom = UDim.new(0, 2),
				}),

				SpeedUpgradeCard(props.OnUpgradeSpeed),
			}),
		})
	end
end

return PressUpgradePanel
