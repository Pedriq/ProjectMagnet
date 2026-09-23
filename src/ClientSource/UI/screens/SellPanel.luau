local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local SellItemCard = require(ReplicatedStorage.ClientSource.UI.components.SellItemCard)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local EdgeAccent = require(ReplicatedStorage.ClientSource.UI.components.EdgeAccent)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = vide.create
local indexes = vide.indexes
local show = vide.show

-- Папки может не быть в плейсе — тогда у карточек просто нет 3D-превью.
local treasureModels = ReplicatedStorage:WaitForChild("Assets"):FindFirstChild("Treasures")

--[[
	SellPanel — окно продажи принесённого лута (по макету, зелёная тема).

	  ┌─ Sell Loot ─────────────────────────────── [✕] ┐
	  │  ┌ +$921.8T           [ Sell All ] [ Sell x2 ] ┐│  ← итог + массовые кнопки
	  │  ┌ [ico] Spirit Feather x2  +$242T [Sell][Lock]┐│
	  │  ┌ [ico] Fate Dice          +$429T [Sell][Lock]┐│  ← прокручиваемый список
	  │  ...                                            │
	  └────────────────────────────────────────────────┘

	Предметы берутся из Data.items (склад — сюда попадает лут после сейв-зоны),
	группируются по имени (стопки «xN»). Все цены — с учётом
	Data.fullCashMultiplier() (rebirth + временный бафф + постоянный
	донат-множитель — та же формула, что и сервер в PlayerTreasureManager).

	Продаёт сервер (PlayerManagerService: SellItems / SellAllItems); Data.items и
	Data.money обновятся через ProfileService.UpdateSpecificData.

	ИКОНОК предметов пока нет. Заблокированные (Lock) предметы — не в rawTotal/
	isEmpty, сервер их тоже не продаёт ни по одному, ни через Sell All/x2
	(см. PlayerManagerService:ToggleItemLock, PlayerTreasureManager:SellItem).

	Использование:
	  SellPanel({ OnClose, OnSellItem = fn(ids), OnSellAll, OnSellX2, OnLock = fn(name) })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnSellItem: (ids: { string }) -> (),
	OnSellAll: () -> (),
	OnSellX2: () -> (),
	OnLock: (name: string) -> (),
}

local GREEN = Color3.fromRGB(108, 206, 84)
local BODY = Color3.fromRGB(16, 34, 20)
local GOLD = Color3.fromRGB(255, 190, 62)
local SELL_ALL_COLOR = Color3.fromRGB(70, 200, 64)
local PRICE_COLOR = Color3.fromRGB(60, 255, 90)

-- Data.items -> отсортированный список стопок { Name, Price, Rarity, Count, Ids }
local function groupedItems()
	local items = Data.items()

	local groups: { [string]: any } = {}
	local order: { string } = {}
	for id, item in pairs(items) do
		local name = item.Name or "Unknown"
		local g = groups[name]
		if not g then
			g = { Name = name, Price = tonumber(item.Price) or 0, Rarity = item.Rarity, Count = 0, Ids = {} }
			groups[name] = g
			table.insert(order, name)
		end
		g.Count += 1
		table.insert(g.Ids, id)
	end

	table.sort(order, function(a, b)
		return groups[a].Price * groups[a].Count > groups[b].Price * groups[b].Count
	end)

	local list = {}
	for _, name in ipairs(order) do
		table.insert(list, groups[name])
	end
	return list
end

local function isLocked(name: string): boolean
	return Data.lockedItems()[name] == true
end

-- "Пусто" = нет предметов, которые реально можно продать (заблокированные не
-- считаются) — иначе Sell All/Sell x2 были бы активны, даже когда всё в замке.
local function isEmpty(): boolean
	for _, item in pairs(Data.items()) do
		if not isLocked(item.Name) then
			return false
		end
	end
	return true
end

-- Сумма всех Price (числом) без множителя. Заблокированные предметы не
-- считаются — Sell All/Sell x2 их всё равно не продают (см. PlayerTreasureManager).
local function rawTotal(): number
	local sum = 0
	for _, item in pairs(Data.items()) do
		if not isLocked(item.Name) then
			sum += tonumber(item.Price) or 0
		end
	end
	return sum
end

local function totalText(): string
	return "+$" .. Format.short(EtNum.mul(rawTotal(), Data.fullCashMultiplier()))
end

local function SellPanel(props: Props)
	--== верхняя карточка: итог + Sell All / Sell x2 =========================
	local function summaryCard()
		return create("Frame")({
			Name = "Summary",
			LayoutOrder = 0,
			Size = UDim2.new(1, -6, 0, 96),
			BackgroundColor3 = GOLD,

			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 150, 40)),
			}),
			create("UIStroke")({ Thickness = 3, Color = Color3.new(0, 0, 0), Transparency = 0.1 }),
			create("ImageLabel")({
				Name = "Texture",
				ZIndex = 0,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(96, 96),
				ImageTransparency = 0.76,
				Image = Format.asset("137638295200351"),
				create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			}),

			create("TextLabel")({
				Name = "Total",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 16, 0.5, 0),
				Size = UDim2.new(1, -16 - 150, 1, 0),
				Font = Enum.Font.GothamBlack,
				TextSize = 34,
				TextColor3 = PRICE_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = totalText,

				create("UIStroke")({ Thickness = 3, Color = Color3.new(0, 0, 0), LineJoinMode = Enum.LineJoinMode.Round }),
			}),

			create("Frame")({
				Name = "Buttons",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(140, 78),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 8),
				}),

				WideButton({
					LayoutOrder = 1,
					Text = "Sell All",
					Size = UDim2.fromOffset(140, 34),
					TextSize = 19,
					Color = SELL_ALL_COLOR,
					Disabled = isEmpty,
					OnActivated = props.OnSellAll,
				}),
				WideButton({
					LayoutOrder = 2,
					Text = "Sell x2",
					Size = UDim2.fromOffset(140, 34),
					TextSize = 19,
					Color = GOLD,
					TextColor = Color3.fromRGB(255, 255, 255),
					Disabled = isEmpty,
					OnActivated = props.OnSellX2,
				}),
			}),

			EdgeAccent({ Radius = UDim.new(0, 6) }),
		})
	end

	return function()
		return Panel({
			ZIndex = 10,
			Icon = "119796584892549",
			Size = UDim2.fromOffset(560, 560),
			OnClose = props.OnClose,

			Title = "Sell Loot",
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

				summaryCard(),

				indexes(groupedItems, function(group, i)
					return SellItemCard({
						LayoutOrder = i,
						Name = function()
							return group().Name
						end,
						Count = function()
							return group().Count
						end,
						NameColor = function()
							return RarityColors.get(group().Rarity)
						end,
						Model = function()
							return treasureModels and treasureModels:FindFirstChild(group().Name)
						end,
						PriceText = function()
							local g = group()
							return "+$" .. Format.short(EtNum.mul(g.Price * g.Count, Data.fullCashMultiplier()))
						end,
						Locked = function()
							return isLocked(group().Name)
						end,
						OnSell = function()
							props.OnSellItem(group().Ids)
						end,
						OnLock = function()
							props.OnLock(group().Name)
						end,
					})
				end),

				show(isEmpty, function()
					return create("TextLabel")({
						Name = "Empty",
						LayoutOrder = 999,
						Size = UDim2.new(1, 0, 0, 120),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamMedium,
						TextSize = 18,
						TextColor3 = Color3.fromRGB(200, 210, 200),
						Text = "No loot to sell — go collect some!",
						TextWrapped = true,
					})
				end),
			}),
		})
	end
end

return SellPanel
