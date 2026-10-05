local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local BoostCard = require(ReplicatedStorage.ClientSource.UI.components.BoostCard)
local BuffConfig = require(ReplicatedStorage.SharedSource.Datas.BuffConfig)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local Data = require(ReplicatedStorage.ClientSource.UI.data)

local OPMagnetCard = require(ReplicatedStorage.ClientSource.UI.components.OPMagnetCard)
local ZoneCard = require(ReplicatedStorage.ClientSource.UI.components.ZoneCard)

local create = vide.create
local indexes = vide.indexes
local show = vide.show
local source = vide.source
local changed = vide.changed

export type Props = {
	OnClose: () -> (),
	OnBuyBoost: ((productId: number) -> ())?,
	-- magnetKey — внутренний ключ MagnetData (MagnetData.Wraithcoil/.WarringWingcoil),
	-- не отображаемое имя (OPMagnetCard.Props.Name может содержать пробелы).
	OnBuyOPMagnet: ((magnetKey: string) -> ())?,
	OnEquipOPMagnet: ((magnetKey: string) -> ())?,
	-- zoneId — Attribute "ZoneId" модели зоны; сервер сам найдёт gamePassId и не откроет
	-- окно покупки, если зона уже куплена (AutoClickZoneService:PromptZonePurchase).
	OnBuyZone: ((zoneId: string) -> ())?,
}

local function opMagnetOwned(magnetKey: string): boolean
	return Data.ownedMagnets()[magnetKey] == true
end

local function opMagnetEquipped(magnetKey: string): boolean
	local w = Data.magnet()
	return type(w) == "table" and MagnetData.resolveKey(w.Name) == magnetKey
end

-- Категория: ширина — доля холста, ВЫСОТА — пиксели, посчитанные из реальной ширины
-- скролла (ширина / 2.5). Раньше высоту давал UIAspectRatioConstraint, а при
-- AutomaticCanvasSize высота такого фрейма зависит от холста, а холст — от высоты:
-- цикл, из-за которого низ списка (карточки донатных мечей) оказывался за пределами
-- прокрутки.
local CATEGORY_WIDTH = 0.93
local CATEGORY_ASPECT = 2.5
local CATEGORY_MIN_HEIGHT = 140

local function category(title: string, order: number, cards: { Instance }, heightPx: () -> number)
	return create("Frame")({
		Name = title,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = function()
			return UDim2.new(CATEGORY_WIDTH, 0, 0, heightPx())
		end,
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

-- Секция «Training Zones»: платные автоклик-зоны вертикальным списком от меньшего
-- множителя к большему (порядок задаёт сервер, Data.zoneCatalog). Отдельная «плашка» с
-- золотой рамкой и тёмным фиолетово-синим градиентом — визуально выделена из остального
-- магазина. Скрыта, пока каталог не пришёл (или зон нет).
local GOLD = Color3.fromRGB(255, 196, 56)

local function zoneSection(order: number, props: Props)
	return create("Frame")({
		Name = "Training Zones",
		LayoutOrder = order,
		Size = UDim2.fromScale(0.93, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,

		create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(34, 24, 66), Color3.fromRGB(14, 22, 44)),
		}),
		create("UIStroke")({
			Thickness = 3,
			Color = GOLD,
			Transparency = 0.15,
		}),
		create("UIPadding")({
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
		}),
		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),

		-- заголовок секции
		create("Frame")({
			Name = "Header",
			LayoutOrder = 0,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 62),

			create("TextLabel")({
				Name = "Title",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, 36),
				Font = Enum.Font.GothamBlack,
				Text = "TRAINING ZONES",
				TextSize = 32,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Left,

				create("UIStroke")({ Thickness = 3, Color = Color3.new(0, 0, 0) }),
				create("UIGradient")({
					Rotation = 0,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 190)),
						ColorSequenceKeypoint.new(0.5, GOLD),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 60)),
					}),
				}),
			}),
			create("TextLabel")({
				Name = "Subtitle",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 38),
				Size = UDim2.new(1, 0, 0, 18),
				Font = Enum.Font.GothamBold,
				Text = "Stand inside a zone to auto-click with a huge multiplier",
				TextSize = 15,
				TextColor3 = Color3.fromRGB(200, 196, 230),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			-- тонкая золотая линия-подчёркивание, тает к правому краю
			create("Frame")({
				Name = "Underline",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 2),
				BorderSizePixel = 0,
				BackgroundColor3 = GOLD,

				create("UIGradient")({
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),

		-- карточки: порядок и Tier приходят с сервера (по возрастанию множителя)
		indexes(Data.zoneCatalog, function(entry, i)
			return ZoneCard({
				LayoutOrder = i,
				Multiplier = entry().Multiplier,
				Title = entry().Title,
				Price = entry().Price,
				Tier = entry().Tier or i,
				Owned = function()
					return Data.ownedZones()[entry().ZoneId] == true
				end,
				OnBuy = function()
					if props.OnBuyZone then
						props.OnBuyZone(entry().ZoneId)
					end
				end,
			})
		end),
	})
end

local function ShopPanel(props: Props)
	return function()
		-- реальная ширина области прокрутки в пикселях (обновляется при ресайзе окна)
		local scrollWidth = source(0)
		local function categoryHeight(): number
			return math.max(math.floor(scrollWidth() * CATEGORY_WIDTH / CATEGORY_ASPECT), CATEGORY_MIN_HEIGHT)
		end

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
			TitleColor = Theme.ShopTitle, -- чистый янтарь (UI.theme, раздел Магазин)
			-- Свой TileSize не задаём (дефолт Panel.luau — плитка размером с полоску
			-- тайтла); прозрачность текстуры — общая для всех панелей (UI.theme).
			TitleImage = Theme.PanelTitleTexture,
			TitleImageTransparency = Theme.PanelTitleTextureTransparency,
			BodyColor = Theme.ShopBody,
			BodyTransparency = Theme.PanelBodyTransparency,
			BodyInset = 22,
			BodyPadding = 8,
			StrokeThickness = Theme.PanelStrokeThickness,
			List = false,
			OnClose = props.OnClose,

			create("ScrollingFrame")({
				Name = "ShopScroll",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y, -- секция зон выше фиксированных категорий
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 6,
				ScrollBarImageColor3 = Color3.new(0, 0, 0),
				ScrollBarImageTransparency = 0.25,
				ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,

				-- измеряем ширину области прокрутки: от неё считается высота категорий
				changed("AbsoluteSize", function(size: Vector2)
					scrollWidth(size.X)
				end),
				-- запас снизу, чтобы низ последней карточки всегда был виден при прокрутке
				create("UIPadding")({
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 18),
				}),

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
					-- ОФФСЕТ, не scale: при AutomaticCanvasSize scale-отступ считается от самой
					-- растущей канвы и раздувался — карточки уезжали вниз за границы панели
					Padding = UDim.new(0, 12),
				}),
				category("Boosts", 1, cards, categoryHeight),
				show(function()
					return #Data.zoneCatalog() > 0
				end, function()
					return zoneSection(2, props)
				end),
				category("OP Magnets", 3, {
					OPMagnetCard({
						Name = "Wraithcoil",
						Rarity = MagnetData.Wraithcoil.Rare,
						ModelNames = MagnetData.assetNameCandidates("Wraithcoil"),
						Bonus = 100,
						Price = 499,
						LayoutOrder = 1,
						Owned = function()
							return opMagnetOwned("Wraithcoil")
						end,
						Equipped = function()
							return opMagnetEquipped("Wraithcoil")
						end,
						OnBuy = function()
							if props.OnBuyOPMagnet then
								props.OnBuyOPMagnet("Wraithcoil")
							end
						end,
						OnEquip = function()
							if props.OnEquipOPMagnet then
								props.OnEquipOPMagnet("Wraithcoil")
							end
						end,
					}),
					OPMagnetCard({
						Name = "Warring Wingcoil",
						Rarity = MagnetData.WarringWingcoil.Rare,
						ModelNames = MagnetData.assetNameCandidates("WarringWingcoil"),
						Bonus = 300,
						Price = 1499,
						Red = true,
						LayoutOrder = 2,
						Owned = function()
							return opMagnetOwned("WarringWingcoil")
						end,
						Equipped = function()
							return opMagnetEquipped("WarringWingcoil")
						end,
						OnBuy = function()
							if props.OnBuyOPMagnet then
								props.OnBuyOPMagnet("WarringWingcoil")
							end
						end,
						OnEquip = function()
							if props.OnEquipOPMagnet then
								props.OnEquipOPMagnet("WarringWingcoil")
							end
						end,
					}),
				}, categoryHeight),
			}),
		})
	end
end

return ShopPanel
