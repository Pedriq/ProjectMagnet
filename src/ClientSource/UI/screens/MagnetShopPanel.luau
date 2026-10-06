local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local MagnetCard = require(ReplicatedStorage.ClientSource.UI.components.MagnetCard)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Tutorial = require(ReplicatedStorage.ClientSource.UI.tutorial)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = vide.create
local show = vide.show

-- Модель может быть названа Display/Name/ключом — см. findMagnetModel ниже
-- и MagnetData.assetNameCandidates (та же логика, что у MagnetHandler:GiveMagnet
-- на сервере).
local weponFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Magnets")

--[[
	MagnetShopPanel — окно покупки мечей «Cutters» (по макету).

	  ┌─ Cutters ────────────────────────────────── [X] ┐
	  │  [img] Sword Saw   Legendary   💪 +267K   [$280M]│
	  │                                           [R$799]│  ← прокручиваемый список
	  │  [img] Axe         Mythic✨    💪 +558K   [Equip]│
	  │  ...                                             │
	  └─────────────────────────────────────────────────┘

	Карточки строятся из MagnetData.Order. Стартовый FridgeMagnet (нет цены) не продаётся —
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

-- Модель может быть названа ЛИБО Display (если ассет уже переименован под
-- магнит), ЛИБО старым Name, ЛИБО самим ключом — перебираем все варианты.
local function findMagnetModel(key: string): Instance?
	for _, candidate in ipairs(MagnetData.assetNameCandidates(key)) do
		local found = weponFolder:FindFirstChild(candidate)
		if found then
			return found
		end
	end
	return nil
end

-- Донатные (Game Pass) мечи, самый сильный первым: у них нет Magnetism в конфиге —
-- сила считается от лучшего обычного меча игрока (MagnetData.effectiveMagnetism).
local function opMagnetKeys(): { string }
	local keys = table.clone(MagnetData.GamePassMagnets)
	table.sort(keys, function(a, b)
		local ma = MagnetData[a].Dynamic and MagnetData[a].Dynamic.Multiplier or 0
		local mb = MagnetData[b].Dynamic and MagnetData[b].Dynamic.Multiplier or 0
		return ma > mb
	end)
	return keys
end

local function MagnetShopPanel(props: Props)
	-- premium = купленный донатный меч: тёмно-синяя карточка, поднимается наверх списка
	local function makeCard(name: string, order: number, premium: boolean?)
		local cfg = MagnetData[name]
		local fx = MagnetData.effectsFor(cfg)

		return MagnetCard({
			LayoutOrder = order,
			Premium = premium,
			Display = cfg.Display or cfg.Name,
			Rarity = cfg.Rare,
			RarityColor = RarityColors.get(cfg.Rare),
			MagnetismText = if premium
				then function()
					return "+" .. Format.short(MagnetData.effectiveMagnetism(name, Data.ownedMagnets())) .. " Magnetism"
				end
				else "+" .. Format.short(cfg.Magnetism) .. " Magnetism",
			Model = findMagnetModel(name),

			-- туториал: «это следующий магнит, который стоит купить»
			Highlight = if premium
				then nil
				else function()
					return Tutorial.highlightMagnet() == name
				end,
			HighlightLabel = "BUY THIS",
			-- остальные карточки гаснут, пока туториал подсвечивает один магнит
			Dim = function()
				local target = Tutorial.highlightMagnet()
				return target ~= nil and target ~= name
			end,

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

		-- Купленные OP-магниты — в самом верху (отрицательный LayoutOrder). Карточка
		-- появляется ТОЛЬКО когда владение подтверждено: Data.ownedMagnets обновляется
		-- сервером после успешной покупки Game Pass (MagnetGamePassPurchaseHandler ->
		-- SetMagnetOwned) и при входе из сохранённого профиля.
		local opKeys = opMagnetKeys()
		for i, name in ipairs(opKeys) do
			table.insert(
				cards,
				show(function()
					return owns(name)
				end, function()
					return makeCard(name, i - #opKeys - 1, true)
				end)
			)
		end

		for i, name in ipairs(MagnetData.Order) do
			table.insert(cards, makeCard(name, i))
		end

		return Panel({
			ZIndex = 10,
			Icon = "82923936325309",
			Size = UDim2.fromOffset(620, 560),
			OnClose = props.OnClose,

			Title = "Magnets",
			TitleColor = Theme.titleColor("Electric"),
			BodyColor = Theme.bodyColor("Electric"),
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
