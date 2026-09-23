local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local UpgradeCard = require(ReplicatedStorage.ClientSource.UI.components.UpgradeCard)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local StatUpgradesConfig = require(ReplicatedStorage.SharedSource.Datas.StatUpgradesConfig)

local create = vide.create

--[[
	UpgradesPanel — окно прокачки статов (по макету, зелёная тема).

	  ┌─ Upgrades ───────────────────────────────── [X] ┐
	  │  [icon] Range   Lv.32   +7.5% Atk. Radius  [$..] │
	  │                                           [R$..] │  ← прокручиваемый список
	  │  [icon] Agility Lv.31   +10% Atk. Speed    [$..] │
	  │  ...                                             │
	  └─────────────────────────────────────────────────┘

	Список карточек строится из StatUpgradesConfig.Order. Уровень — из
	Data.upgradeLevels, цена — StatUpgradesConfig.CostFor(level), кнопка Money
	гаснет, когда денег не хватает или достигнут максимум.

	Использование:
	  UpgradesPanel({ OnClose = fn, OnBuyMoney = fn(statKey), OnBuyRobux = fn(statKey) })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnBuyMoney: (statKey: string) -> (),
	OnBuyRobux: (statKey: string) -> (),
}

local GREEN = Color3.fromRGB(108, 206, 84)
local BODY = Color3.fromRGB(16, 34, 20)

local function levelOf(statKey: string): number
	return Data.upgradeLevels()[statKey] or 1
end

local function UpgradesPanel(props: Props)
	local function makeCard(statKey: string, order: number)
		local cfg = StatUpgradesConfig.Stats[statKey]

		local function level()
			return levelOf(statKey)
		end
		local function cost()
			return StatUpgradesConfig.CostFor(statKey, level())
		end
		local function atMax()
			return level() >= cfg.MaxLevel
		end

		return UpgradeCard({
			LayoutOrder = order,
			Title = cfg.Title,
			Bonus = cfg.Bonus,
			Icon = cfg.Icon,

			Level = level,
			CostText = function()
				return if atMax() then "MAX" else "$" .. Format.short(cost())
			end,
			RobuxText = function()
				return if cfg.RobuxPrice > 0 then `R$ {cfg.RobuxPrice}` else "R$ Buy"
			end,

			MoneyDisabled = function()
				return atMax() or EtNum.me(cost(), Data.money())
			end,
			OnBuyMoney = function()
				props.OnBuyMoney(statKey)
			end,
			OnBuyRobux = function()
				props.OnBuyRobux(statKey)
			end,
		})
	end

	return function()
		local cards = {}
		for i, statKey in ipairs(StatUpgradesConfig.Order) do
			table.insert(cards, makeCard(statKey, i))
		end

		return Panel({
			ZIndex = 10,
			Icon = "136736672080005",
			Size = UDim2.fromOffset(560, 520),
			OnClose = props.OnClose,

			Title = "Upgrades",
			TitleColor = GREEN,
			BodyColor = BODY,
			BodyTransparency = 0.55,
			StrokeColor = Color3.fromRGB(0, 0, 0),
			TitleImage = "rbxassetid://137638295200351",
			TitleImageTransparency = 0.6,
			StrokeThickness = 3,

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
				VerticalScrollBarInset = Enum.ScrollBarInset.Always, -- иначе скроллбар перекрывает правый край карточек
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

				table.unpack(cards),
			}),
		})
	end
end

return UpgradesPanel
