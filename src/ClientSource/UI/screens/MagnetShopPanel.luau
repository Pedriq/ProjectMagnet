local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local MagnetCard = require(ReplicatedStorage.ClientSource.UI.components.MagnetCard)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = vide.create

-- Модели мечей названы отображаемым именем (cfg.Name), а не ключом MagnetData —
-- см. MagnetHandler:GiveMagnet на сервере, где это уже учтено.
local weponFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Magnets")

--[[
	MagnetShopPanel — окно покупки мечей «Cutters» (по макету).

	  ┌─ Cutters ────────────────────────────────── [X] ┐
	  │  [img] Sword Saw   Legendary   💪 +267K   [$280M]│
	  │                                           [R$799]│  ← прокручиваемый список
	  │  [img] Axe         Mythic✨    💪 +558K   [Equip]│
	  │  ...                                             │
	  └─────────────────────────────────────────────────┘

	Карточки строятся из MagnetData.Order. Стартовый Stick (нет цены) не продаётся —
	у него только Equip/Equipped.

	Покупку (за Money — PlayerManagerService:BuyMagnet, за Robux — дев-продукт
	MagnetData[name].RobuxProductId) и экипировку делает сервер; Data.magnet и
	Data.ownedMagnets обновятся через ProfileService.UpdateSpecificData.

	Использование:
	  MagnetShopPanel({ OnClose, OnBuyMoney = fn(name), OnBuyRobux = fn(name), OnEquip = fn(name) })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnBuyMoney: (magnetName: string) -> (),
	OnBuyRobux: (magnetName: string) -> (),
	OnEquip: (magnetName: string) -> (),
}

local BLUE = Color3.fromRGB(122, 138, 248)
local BODY = Color3.fromRGB(16, 20, 34)

local function owns(name: string): boolean
	return Data.ownedMagnets()[name] == true
end

local function equipped(name: string): boolean
	local w = Data.magnet()
	if type(w) ~= "table" then
		return false
	end

	-- resolveKey — на случай профилей, у которых в Magnet.Name осело отображаемое
	-- имя вместо ключа (баг EquipMagnet, см. MagnetData.resolveKey): раньше из-за
	-- этого "Equipped" показывался только для Stick (у него имя совпадает с ключом).
	return MagnetData.resolveKey(w.Name) == name
end

local function MagnetShopPanel(props: Props)
	local function makeCard(name: string, order: number)
		local cfg = MagnetData[name]
		local fx = MagnetData.effectsFor(cfg)

		return MagnetCard({
			LayoutOrder = order,
			Display = cfg.Display or cfg.Name,
			Rarity = cfg.Rare,
			RarityColor = RarityColors.get(cfg.Rare),
			MagnetismText = "+" .. Format.short(cfg.Magnetism) .. " Magnetism",
			Model = weponFolder:FindFirstChild(cfg.Name),

			Purchasable = cfg.Price ~= nil,
			Owned = function()
				return owns(name)
			end,
			Equipped = function()
				return equipped(name)
			end,

			MoneyText = function()
				return if cfg.Price then "$" .. Format.short(cfg.Price) else ""
			end,
			MoneyDisabled = function()
				return not owns(name) and cfg.Price ~= nil and EtNum.me(cfg.Price, Data.money())
			end,
			RobuxText = function()
				return if cfg.RobuxPrice and cfg.RobuxPrice > 0 then `R$ {cfg.RobuxPrice}` else "R$ Buy"
			end,

			OnBuyMoney = function()
				props.OnBuyMoney(name)
			end,
			OnBuyRobux = function()
				props.OnBuyRobux(name)
			end,
			OnEquip = function()
				props.OnEquip(name)
			end,

			TextEffect = fx.Text,
			CardEffect = fx.Card,
		})
	end

	return function()
		local cards = {}
		for i, name in ipairs(MagnetData.Order) do
			table.insert(cards, makeCard(name, i))
		end

		return Panel({
			ZIndex = 10,
			Icon = "96772289336842",
			Size = UDim2.fromOffset(620, 560),
			OnClose = props.OnClose,

			Title = "Magnets",
			TitleColor = BLUE,
			BodyColor = BODY,
			BodyTransparency = 0.5,
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

return MagnetShopPanel
