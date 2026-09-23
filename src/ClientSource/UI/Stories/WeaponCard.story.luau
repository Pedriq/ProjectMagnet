local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vide = require(ReplicatedStorage.Packages.Vide)
local WeaponCard = require(ReplicatedStorage.ClientSource.UI.components.WeaponCard)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)

local create = Vide.create
local source = Vide.source

-- Три карточки: обычная (не куплена), Mythic с эффектами (куплена), Mythic (надета).
local story = {
	vide = Vide,
	story = function()
		local ownedSaber = source(true)
		local equippedName = source("Saber")

		local function card(props)
			return WeaponCard(props)
		end

		return create("Frame")({
			Size = UDim2.fromOffset(640, 560),
			BackgroundColor3 = Color3.fromRGB(16, 20, 34),

			create("UIListLayout")({
				Padding = UDim.new(0, 12),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			card({
				LayoutOrder = 1,
				Display = "Sword Saw",
				Rarity = "Legendary",
				RarityColor = RarityColors.get("Legendary"),
				StrengthText = "+267K Strength",
				Icon = "",
				Purchasable = true,
				Owned = function()
					return false
				end,
				Equipped = function()
					return false
				end,
				MoneyText = function()
					return "$280M"
				end,
				MoneyDisabled = function()
					return false
				end,
				RobuxText = function()
					return "R$ 799"
				end,
				OnBuyMoney = function()
					print("buy Sword Saw")
				end,
				OnBuyRobux = function()
					print("robux Sword Saw")
				end,
				TextEffect = 0,
				CardEffect = 0,
			}),

			card({
				LayoutOrder = 2,
				Display = "Axe",
				Rarity = "Mythic",
				RarityColor = RarityColors.get("Mythic"),
				StrengthText = "+558K Strength",
				Icon = "",
				Purchasable = true,
				Owned = ownedSaber,
				Equipped = function()
					return equippedName() == "Axe"
				end,
				MoneyText = function()
					return "$45B"
				end,
				MoneyDisabled = function()
					return false
				end,
				RobuxText = function()
					return "R$ 999"
				end,
				OnEquip = function()
					equippedName("Axe")
				end,
				TextEffect = 3,
				CardEffect = 4, -- радуга
			}),

			card({
				LayoutOrder = 3,
				Display = "Reaper",
				Rarity = "Secret",
				RarityColor = RarityColors.get("Secret"),
				StrengthText = "+8M Strength",
				Icon = "",
				Purchasable = true,
				Owned = function()
					return true
				end,
				Equipped = function()
					return equippedName() == "Reaper"
				end,
				MoneyText = function()
					return "$180T"
				end,
				RobuxText = function()
					return "R$ 1999"
				end,
				OnEquip = function()
					equippedName("Reaper")
				end,
				TextEffect = 2,
				CardEffect = 3, -- смена цветов
			}),

			card({
				LayoutOrder = 4,
				Display = "Saber",
				Rarity = "Divine",
				RarityColor = RarityColors.get("Divine"),
				StrengthText = "+1.1M Strength",
				Icon = "",
				Purchasable = true,
				Owned = function()
					return false
				end,
				Equipped = function()
					return false
				end,
				MoneyText = function()
					return "$2.2T"
				end,
				MoneyDisabled = function()
					return false
				end,
				RobuxText = function()
					return "R$ 1299"
				end,
				OnBuyMoney = function()
					print("buy Saber")
				end,
				TextEffect = 3,
				CardEffect = 2, -- полосы света
			}),
		})
	end,
}

return story
