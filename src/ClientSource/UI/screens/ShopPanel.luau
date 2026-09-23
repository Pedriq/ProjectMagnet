local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local BoostCard = require(ReplicatedStorage.ClientSource.UI.components.BoostCard)
local BuffConfig = require(ReplicatedStorage.SharedSource.Datas.BuffConfig)
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local OPSwordCard = require(ReplicatedStorage.ClientSource.UI.components.OPSwordCard)

local create = vide.create

export type Props = {
	OnClose: () -> (),
	OnBuyBoost: ((productId: number) -> ())?,
	-- weaponKey — внутренний ключ WeaponData (WeaponData.Wraithflame/.WarringWingblade),
	-- не отображаемое имя (OPSwordCard.Props.Name может содержать пробелы).
	OnBuyOPSword: ((weaponKey: string) -> ())?,
	OnEquipOPSword: ((weaponKey: string) -> ())?,
}

local function opSwordOwned(weaponKey: string): boolean
	return Data.ownedWeapons()[weaponKey] == true
end

local function opSwordEquipped(weaponKey: string): boolean
	local w = Data.weapon()
	return type(w) == "table" and WeaponData.resolveKey(w.Name) == weaponKey
end

local function category(title: string, order: number, cards: { Instance })
	return create("Frame")({
		Name = title,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.93, 0),
		create("UIAspectRatioConstraint")({
			AspectRatio = 2.5,
			DominantAxis = Enum.DominantAxis.Width,
			AspectType = Enum.AspectType.ScaleWithParentSize,
		}),
		create("TextLabel")({
			Name = "CategoryTitle",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.025),
			Size = UDim2.fromScale(1, 0.13),
			Text = title,
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			create("UIStroke")({ Thickness = 3, Color = Color3.new(0, 0, 0) }),
		}),
		create("Frame")({
			Name = "Products",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0, 0.19),
			Size = UDim2.fromScale(1, 0.78),
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.05, 0),
			}),
			table.unpack(cards),
		}),
	})
end

local function ShopPanel(props: Props)
	return function()
		local cards = {}
		for index, boost in ipairs(BuffConfig.Boosts) do
			table.insert(
				cards,
				BoostCard({
					LayoutOrder = index,
					Title = boost.Title,
					Minutes = boost.Minutes,
					Price = boost.Price,
					Icon = boost.Icon,
					Money = boost.Type == "Money",
					ProductId = boost.ProductId,
					OnBuy = props.OnBuyBoost,
				})
			)
		end

		return Panel({
			ZIndex = 10,
			ScaleLayout = true,
			Size = UDim2.fromScale(0.8, 0.76),
			Title = "Shop",
			Icon = "95100426738981",
			TitleHeight = 75,
			TitleColor = Color3.fromRGB(255, 62, 120),
			-- Раньше тут стояли кастомные TileSize (0.025x0.33 — плитка ~13x13px,
			-- намного мельче, чем в любой другой панели) и Transparency=0.78
			-- (почти невидимо) — текстура технически рисовалась, но на глаз не
			-- читалась. Убрал TileSize (берёт дефолт Panel.luau — плитка размером
			-- с полоску тайтла, как везде) и выровнял прозрачность по остальным
			-- панелям (Sell/Rebirth/Upgrades/WeaponShop — везде 0.6).
			TitleImage = "137638295200351",
			TitleImageTransparency = 0.6,
			BodyColor = Color3.fromRGB(30, 22, 20),
			BodyTransparency = 0.35,
			BodyInset = 22,
			BodyPadding = 8,
			StrokeThickness = 3,
			List = false,
			OnClose = props.OnClose,

			create("ScrollingFrame")({
				Name = "ShopScroll",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromScale(0, 2.4),
				AutomaticCanvasSize = Enum.AutomaticSize.None,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
				ScrollBarImageTransparency = 0.25,
				ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0.01, 0),
				}),
				category("Boosts", 1, cards),
				category("OP Swords", 2, {
					OPSwordCard({
						Name = "Wraithflame",
						Bonus = 100,
						Price = 499,
						LayoutOrder = 1,
						Owned = function()
							return opSwordOwned("Wraithflame")
						end,
						Equipped = function()
							return opSwordEquipped("Wraithflame")
						end,
						OnBuy = function()
							if props.OnBuyOPSword then
								props.OnBuyOPSword("Wraithflame")
							end
						end,
						OnEquip = function()
							if props.OnEquipOPSword then
								props.OnEquipOPSword("Wraithflame")
							end
						end,
					}),
					OPSwordCard({
						Name = "Warring Wingblade",
						Bonus = 300,
						Price = 1499,
						Red = true,
						LayoutOrder = 2,
						Owned = function()
							return opSwordOwned("WarringWingblade")
						end,
						Equipped = function()
							return opSwordEquipped("WarringWingblade")
						end,
						OnBuy = function()
							if props.OnBuyOPSword then
								props.OnBuyOPSword("WarringWingblade")
							end
						end,
						OnEquip = function()
							if props.OnEquipOPSword then
								props.OnEquipOPSword("WarringWingblade")
							end
						end,
					}),
				}),
			}),
		})
	end
end

return ShopPanel
