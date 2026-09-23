local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SocialService = game:GetService("SocialService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Knit = require(ReplicatedStorage.Packages.Knit)

local StatRow = require(ReplicatedStorage.ClientSource.UI.components.StatRow)
local ActiveBuffsBar = require(ReplicatedStorage.ClientSource.UI.components.ActiveBuffsBar)
local XpBar = require(ReplicatedStorage.ClientSource.UI.components.XpBar)
local ActionButton = require(ReplicatedStorage.ClientSource.UI.components.ActionButton)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local BuffBuyButton = require(ReplicatedStorage.ClientSource.UI.components.BuffBuyButton)
local PowerBuyButton = require(ReplicatedStorage.ClientSource.UI.components.PowerBuyButton)
local ShopPanel = require(ReplicatedStorage.ClientSource.UI.screens.ShopPanel)
local RebirthPanel = require(ReplicatedStorage.ClientSource.UI.screens.RebirthPanel)
local UpgradesPanel = require(ReplicatedStorage.ClientSource.UI.screens.UpgradesPanel)
local SellPanel = require(ReplicatedStorage.ClientSource.UI.screens.SellPanel)
local MagnetShopPanel = require(ReplicatedStorage.ClientSource.UI.screens.MagnetShopPanel)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local WorldState = require(ReplicatedStorage.ClientSource.UI.worldState)
local BaseStructures = require(ReplicatedStorage.ClientSource.UI.baseStructures)
local viewportScale = require(ReplicatedStorage.ClientSource.UI.viewportScale)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local LevelCurve = require(ReplicatedStorage.SharedSource.Datas.LevelCurve)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)
local PermanentMultiplierConfig = require(ReplicatedStorage.SharedSource.Datas.PermanentMultiplierConfig)
local PowerPackConfig = require(ReplicatedStorage.SharedSource.Datas.PowerPackConfig)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local source = vide.source
local show = vide.show
local switch = vide.switch
local effect = vide.effect
local cleanup = vide.cleanup

-- Фон за открытой панелью: размытие + лёгкое отдаление камеры (расширение FOV).
local PANEL_BLUR_SIZE = 18
local PANEL_FOV_OFFSET = 6
local PANEL_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[
	HUD — контент постоянного игрового оверлея (Frame на весь экран).
	Данные — из Data (реактивное зеркало профиля).
]]

-- === производные XP-бара из силы + уровня ===
local function xpInLevel() -- EtNum: сколько силы набрано внутри текущего уровня
	return EtNum.sub(Data.magnetism(), LevelCurve.TotalForLevel(Data.level()))
end

local function xpRequired(): number -- сколько нужно набрать за уровень
	return LevelCurve.RequiredForLevel(Data.level())
end

local function xpCurrent(): number -- то же, но числом (для текста), >= 0
	return math.max(EtNum.toNumber(xpInLevel()), 0)
end

local function xpProgress(): number -- 0..1 для заполнения
	local req = xpRequired()
	if req <= 0 then
		return 1
	end
	local frac = xpCurrent() / req
	if frac ~= frac then -- NaN на очень больших числах
		frac = 1
	end
	return math.clamp(frac, 0, 1)
end

-- === прогресс до доступности ребёрса (для бейджа на кнопке Rebirth) ===
local function rebirthReqLevel(): number
	return RebirthConfig.RequiredLevelForRebirth(Data.rebirths())
end

local function canRebirth(): boolean
	return Data.level() >= rebirthReqLevel()
end

local BADGE_NORMAL_COLOR = Color3.fromRGB(240, 245, 240) -- обычный (как текст кнопки)
local BADGE_ACCENT_COLOR = Color3.fromRGB(95, 247, 95) -- зелёный, когда что-то готово/активно

local function rebirthBadgeText(): string
	if canRebirth() then
		return "100%"
	end
	local req = rebirthReqLevel()
	if req <= 0 then
		return ""
	end
	return `{math.floor(math.clamp(Data.level() / req, 0, 1) * 100)}%`
end

local function rebirthBadgeColor(): Color3
	return canRebirth() and BADGE_ACCENT_COLOR or BADGE_NORMAL_COLOR
end

-- === бонус за друзей в сессии (для бейджа на кнопке Invite) ===
-- 0 друзей -> "0%" (бонуса нет), 1 друг -> "5%", 2 друга -> "10%" и т.д.
-- (см. FriendBonusHandler на сервере — он же реально применяет бонус к силе за клик)
local function inviteBadgeText(): string
	return `{Data.friendBonusPercent()}%`
end

local function inviteBadgeColor(): Color3
	return Data.friendBonusPercent() > 0 and BADGE_ACCENT_COLOR or BADGE_NORMAL_COLOR
end

-- === постоянные донат-множители (BuffBuyButton: "x2 Magnetism" / "x2 Money") ===
-- Следующая непройденная ступень для текущего купленного множителя игрока;
-- nil, если все ступени уже куплены (см. PermanentMultiplierConfig.NextTier).
local function nextPermanentTier(buffType: string): PermanentMultiplierConfig.Tier?
	local owned = Data.permanentMultipliers()[buffType] or 0
	return PermanentMultiplierConfig.NextTier(buffType, owned)
end

local function hasNextPermanentTier(buffType: string): boolean
	return nextPermanentTier(buffType) ~= nil
end

local function permanentTierTitle(buffType: string, label: string): string
	local tier = nextPermanentTier(buffType)
	return tier and `x{tier.Multiplier} {label}` or ""
end

local function permanentTierPrice(buffType: string): number
	local tier = nextPermanentTier(buffType)
	return tier and tier.Price or 0
end

local function onPermanentTierActivated(buffType: string)
	local tier = nextPermanentTier(buffType)
	if not tier then
		return
	end
	sfx.play("Buy")
	Knit.GetService("PlayerManagerService"):PromptPermanentMultiplierPurchase(tier.ProductId):catch(warn)
end

-- === разовая покупка силы (PowerBuyButton) — без ступеней/владения, см. PowerPackConfig ===
local function onPowerPackActivated(index: number)
	local pack = PowerPackConfig.Packs[index]
	if not pack then
		return
	end
	sfx.play("Buy")
	Knit.GetService("PlayerManagerService"):PromptPowerPackPurchase(pack.ProductId):catch(warn)
end

-- Пригласить друга через нативный Roblox-промпт (не требует депллинков/дев-продуктов).
-- ВАЖНО: PromptGameInvite ничего не показывает в Studio (ни Play Solo, ни Server/Client
-- тесты) — это ограничение самого API, работает только в опубликованной игре через
-- настоящий клиент Roblox. Проверять кнопку нужно там, а не в Studio.
local function onInviteActivated()
	if RunService:IsStudio() then
		warn("[Invite] PromptGameInvite не работает в Studio — протестируй в опубликованной игре.")
		return
	end

	local localPlayer = Players.LocalPlayer
	local ok, err = pcall(function()
		SocialService:PromptGameInvite(localPlayer)
	end)
	if not ok then
		warn("[Invite] PromptGameInvite failed: " .. tostring(err))
	end
end

local function HUD()
	-- какое окно открыто: "shop" | "rebirth" | "upgrades" | "sell" | "magnets" | nil
	local openPanel = source(nil :: string?)
	local function closePanel()
		openPanel(nil)
	end

	--=== NPC-триггеры окон ===================================================
	-- Окна magnets / upgrades / sell открываются не кнопками HUD, а ProximityPrompt'ами
	-- у NPC внутри построек базы мира (Buy / Upgrade / Sell в *BazeZone).
	-- Маппинг построек и разбор промпта — в UI.baseStructures (работает для всех миров).
	local promptConn = ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local key = BaseStructures.panelKeyFromPrompt(prompt)
		if key then
			openPanel(key)
		end
	end)
	cleanup(function()
		promptConn:Disconnect()
	end)

	--=== фон за открытой панелью: размытие + лёгкое отдаление камеры ==========
	local blur = Instance.new("BlurEffect")
	blur.Name = "PanelBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local baseFov = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70

	effect(function()
		local open = openPanel() ~= nil

		TweenService:Create(blur, PANEL_TWEEN, {
			Size = open and PANEL_BLUR_SIZE or 0,
		}):Play()

		local camera = Workspace.CurrentCamera
		if camera then
			TweenService:Create(camera, PANEL_TWEEN, {
				FieldOfView = open and (baseFov + PANEL_FOV_OFFSET) or baseFov,
			}):Play()
		end
	end)

	cleanup(function()
		blur:Destroy()
		if Workspace.CurrentCamera then
			Workspace.CurrentCamera.FieldOfView = baseFov
		end
	end)

	--[[
		Глобальный масштаб интерфейса. Весь UI нарисован пиксельными offset'ами
		под опорное разрешение (см. viewportScale). Обёртка "Content" раздута
		на 1/scale, а UIScale ужимает её обратно: на выходе контейнер точно во
		весь экран, но все пиксельные размеры и отступы детей умножены на scale.
		Доли (fromScale) и привязка к краям экрана при этом сохраняются.
	]]
	local guiScale = viewportScale()

	return create("Frame")({
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		create("Frame")({
			Name = "Content",
			ZIndex = 2, -- выше BuffButtons (см. ниже) — иначе открытые панели (ZIndex 9-10
			-- внутри Content) рисовались бы под ним: BuffButtons — сосед Content, а не
			-- потомок, и ZIndexBehavior у ScreenGui = Sibling (сравнение только среди
			-- прямых соседей).
			BackgroundTransparency = 1,
			Size = function()
				local s = guiScale()
				return UDim2.fromScale(1 / s, 1 / s)
			end,

			create("UIScale")({ Scale = guiScale }),

			--=== ВЕРХ ПО ЦЕНТРУ: полоса опыта / силы, либо кнопка Base =============
			-- Пока игрок «на вылазке» (прошёл Entrance) и не стоит в SaveItemsZone —
			-- вместо XpBar показываем кнопку Base: телепорт на респавн мира.
			create("Frame")({
				Name = "Experience",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 16),
				Size = UDim2.fromOffset(360, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				show(WorldState.showXpBar, function()
					return XpBar({
						Icon = "", -- сюда rbxassetid бицепса
						Large = true,
						Level = Data.level,
						Total = Data.magnetism, -- общая сила под полоской
						Progress = xpProgress,
						Current = xpCurrent,
						Required = xpRequired,
						TrackImage = "137638295200351",
						FillImage = "137638295200351",
					})
				end, function()
					-- кнопка компактная и по центру: оборачиваем в контейнер с центрированием
					return create("Frame")({
						Name = "BaseButtonWrap",
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,

						create("UIListLayout")({
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
						}),

						WideButton({
							Text = "Base",
							Size = UDim2.fromOffset(200, 46),
							TextSize = 24,
							Color = Color3.fromRGB(46, 120, 224), -- синий
							OnActivated = function()
								Knit.GetService("PlayerManagerService"):TeleportToWorldSpawn():catch(warn)
							end,
						}),
					})
				end)
			}),

			--=== ЛЕВЫЙ КРАЙ ПО ЦЕНТРУ: кнопки действий (2 ряда) ==================
			-- Якорь — нижний край блока, чуть ниже центра экрана: блок растёт вверх
			-- и не наезжает на колонку статов в левом нижнем углу при узком экране.
			create("Frame")({
				Name = "Actions",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 0.5, 56),
				Size = UDim2.fromOffset(72 * 2 + 10, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create("UIGridLayout")({
					CellSize = UDim2.fromOffset(72, 72),
					CellPadding = UDim2.fromOffset(10, 10),
					FillDirectionMaxCells = 2, -- 2 в ряду -> Shop/Rebirth сверху, Invite снизу
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
				}),

				ActionButton({
					LayoutOrder = 1,
					Icon = "rbxassetid://95100426738981",
					Text = "Shop",
					OnActivated = function()
						openPanel("shop")
					end,
				}),
				ActionButton({
					LayoutOrder = 2,
					Icon = "rbxassetid://80993270685237",
					Text = "Rebirth",
					CornerBadge = rebirthBadgeText,
					CornerBadgeColor = rebirthBadgeColor,
					OnActivated = function()
						openPanel("rebirth")
					end,
				}),
				-- magnets / upgrades / sell кнопок в HUD нет: их окна открывает
				-- ProximityPrompt у NPC на базе мира (см. подписку PromptTriggered выше
				-- и UI.baseStructures).
				ActionButton({
					LayoutOrder = 3,
					Icon = "rbxassetid://82780444519637",
					Text = "Invite",
					CornerBadge = inviteBadgeText,
					CornerBadgeColor = inviteBadgeColor,
					OnActivated = onInviteActivated,
				}),
			}),

			--=== ЛЕВЫЙ НИЖНИЙ УГОЛ: колонка статов ================================
			create("Frame")({
				Name = "Stats",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -16),
				Size = UDim2.fromOffset(220, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
				}),

				-- 1: заполненность инвентаря переноса
				StatRow({
					LayoutOrder = 1,
					Icon = "rbxassetid://15507675979",
					Text = function()
						return Data.carryCount() .. " / " .. Data.carryCapacity()
					end,
				}),
				-- 2: реберсы
				StatRow({
					LayoutOrder = 2,
					Icon = "rbxassetid://80993270685237",
					Text = function()
						return tostring(Data.rebirths())
					end,
				}),
				-- 3: деньги
				StatRow({
					LayoutOrder = 3,
					Icon = "rbxassetid://117287387544386",
					Large = true,
					TextColor = Color3.fromRGB(95, 247, 95),
					Text = function()
						return Format.short(Data.money())
					end,
				}),
			}),

			--=== ПРАВЫЙ НИЖНИЙ УГОЛ: активные временные баффы =====================
			ActiveBuffsBar(),

			--=== ОКНА ОСНОВНЫХ ФУНКЦИЙ (поверх HUD) =============================
			-- невидимый перехватчик кликов: клик мимо окна закрывает панель
			-- (фон размывается через BlurEffect, см. effect выше — затемнения больше нет)
			show(openPanel, function()
				return create("TextButton")({
					Name = "PanelBackdrop",
					ZIndex = 9,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Modal = true,
					Text = "",
					Activated = closePanel,
				})
			end),

			switch(openPanel)({
				shop = ShopPanel({
					OnClose = closePanel,
					-- Сервер промптит покупку дев-продукта; выдача баффа и обновление
					-- ActiveBuffsBar прилетят через PlayerManagerService.BuffChanged.
					OnBuyBoost = function(productId)
						sfx.play("Buy")
						Knit.GetService("PlayerManagerService"):PromptBuffPurchase(productId):catch(warn)
					end,
					-- Донат-мечи (Wraithflame, Warring Wingblade) — Game Pass, не дев-продукт.
					-- Владение подтвердит сам Roblox (MagnetGamePassPurchaseHandler),
					-- Data.ownedMagnets/Data.magnet прилетят через ProfileService.UpdateSpecificData.
					OnBuyOPMagnet = function(magnetKey)
						Knit.GetService("PlayerManagerService"):PromptMagnetRobuxPurchase(magnetKey):catch(warn)
					end,
					OnEquipOPMagnet = function(magnetKey)
						Knit.GetService("PlayerManagerService"):EquipMagnet(magnetKey):catch(warn)
					end,
				}),
				rebirth = RebirthPanel({
					OnClose = closePanel,
					-- Сервер сам проверит уровень (RebirthHandler:CanRebirth) и применит ребёрс;
					-- Data обновится через ProfileService.UpdateSpecificData.
					OnRebirth = function()
						Knit.GetService("PlayerManagerService"):Rebirth():catch(warn)
					end,
					OnSkip = function()
						warn("[Rebirth] OnSkip: не реализовано")
					end,
				}),
				upgrades = UpgradesPanel({
					OnClose = closePanel,
					-- Сервер сам считает цену и списывает Money (StatUpgradeHandler:BuyWithMoney);
					-- Data (Money + уровень стата) прилетит через ProfileService.UpdateSpecificData.
					OnBuyMoney = function(statKey)
						Knit.GetService("PlayerManagerService"):BuyStatUpgrade(statKey):catch(warn)
					end,
					OnBuyRobux = function(statKey)
						Knit.GetService("PlayerManagerService"):PromptStatRobuxUpgrade(statKey):catch(warn)
					end,
				}),
				magnets = MagnetShopPanel({
					OnClose = closePanel,
					-- Покупку за Money и экипировку считает сервер
					-- (PlayerManagerService:BuyMagnet / :EquipMagnet); Data.magnet и
					-- Data.ownedMagnets прилетят через ProfileService.UpdateSpecificData.
					OnBuyMoney = function(magnetName)
						sfx.play("Buy")
						Knit.GetService("PlayerManagerService"):BuyMagnet(magnetName):catch(warn)
					end,
					-- Обычный меч за Robux, в обход цены Money (дев-продукт,
					-- MagnetData[name].RobuxProductId) — не путать с OP Magnets
					-- (те покупаются за Game Pass через PromptMagnetRobuxPurchase).
					-- Выдача + экипировка — через MarketplaceReceiptRouter
					-- (MagnetRobuxPurchaseHandler), Data.ownedMagnets/Data.magnet
					-- прилетят через ProfileService.UpdateSpecificData.
					OnBuyRobux = function(magnetName)
						Knit.GetService("PlayerManagerService"):PromptMagnetDevProductPurchase(magnetName):catch(warn)
					end,
					OnEquip = function(magnetName)
						Knit.GetService("PlayerManagerService"):EquipMagnet(magnetName):catch(warn)
					end,
				}),
				sell = SellPanel({
					OnClose = closePanel,
					-- Продажа целиком на сервере (PlayerManagerService: SellItems / SellAllItems);
					-- Data.items и Data.money обновятся через ProfileService.UpdateSpecificData.
					OnSellItem = function(ids)
						sfx.play("Sell")
						Knit.GetService("PlayerManagerService"):SellItems(ids):catch(warn)
					end,
					OnSellAll = function()
						sfx.play("Sell")
						Knit.GetService("PlayerManagerService"):SellAllItems():catch(warn)
					end,
					-- Покупка дев-продукта сама продаёт весь инвентарь с x2
					-- (см. SellBoostPurchaseHandler) — отдельного подтверждения
					-- продажи не нужно, чек уже всё делает.
					OnSellX2 = function()
						Knit.GetService("PlayerManagerService"):PromptSellBoostPurchase():catch(warn)
					end,
					-- Переключает блокировку для ВСЕХ предметов с этим именем
					-- (текущих и будущих); Data.lockedItems обновится через
					-- ProfileService.UpdateSpecificData.
					OnLock = function(name)
						Knit.GetService("PlayerManagerService"):ToggleItemLock(name):catch(warn)
					end,
				}),
			}),
		}),

		--=== ПРАВЫЙ КРАЙ, ПО ЦЕНТРУ: покупка x2-баффов (пока без функционала) ===
		-- ВАЖНО: этот блок — прямой ребёнок HUD, НЕ внутри "Content" (см. коммент
		-- ниже про ZIndex). Position/Size — ТОЛЬКО доли экрана (HUD.Size =
		-- fromScale(1,1)), без единого пиксельного офсета и без AutomaticSize:
		-- ширина и высота блока — фиксированные проценты от реального экрана,
		-- поэтому на любом разрешении/соотношении сторон (в т.ч. коротком
		-- альбомном телефоне) блок держит свою долю экрана и не может "потечь"
		-- или вылезти за границы. Раньше здесь была AutomaticSize.Y + офсетная
		-- высота, производная только от ШИРИНЫ (через аспект кнопок) — то есть
		-- высота блока вообще не зависела от реальной высоты экрана и на
		-- невысоких вьюпортах перекрывала весь экран без остатка.
		create("Frame")({
			Name = "BuffButtons",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.995, 0.5),
			Size = UDim2.fromScale(0.14, 0.55),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0.015, 0),
			}),

			-- Постоянный донат-множитель силы: кнопка скрывается сама, когда
			-- куплена последняя ступень (PermanentMultiplierConfig.Tiers.Magnetism).
			show(function()
				return hasNextPermanentTier("Magnetism")
			end, function()
				return BuffBuyButton({
					LayoutOrder = 1,
					Type = "Magnetism",
					Title = function()
						return permanentTierTitle("Magnetism", "Magnetism")
					end,
					Icon = "96772289336842",
					Price = function()
						return permanentTierPrice("Magnetism")
					end,
					OnActivated = function()
						onPermanentTierActivated("Magnetism")
					end,
				})
			end),
			-- То же самое для постоянного множителя денег (Tiers.Money).
			show(function()
				return hasNextPermanentTier("Money")
			end, function()
				return BuffBuyButton({
					LayoutOrder = 2,
					Type = "Money",
					Title = function()
						return permanentTierTitle("Money", "Money")
					end,
					Icon = "117287387544386",
					Price = function()
						return permanentTierPrice("Money")
					end,
					OnActivated = function()
						onPermanentTierActivated("Money")
					end,
				})
			end),

			-- доп. зазор перед колонкой Power — иначе она стоит слишком близко
			-- к "x2 Money" (обычный Padding списка тут был слишком маленьким).
			create("Frame")({
				Name = "PowerColumnSpacer",
				LayoutOrder = 3,
				Size = UDim2.fromScale(1, 0.02),
				BackgroundTransparency = 1,
			}),

			-- === 3 кнопки покупки силы за Robux, друг под другом (сама кнопка — картинка) ===
			create("Frame")({
				Name = "PowerColumn",
				LayoutOrder = 4,
				Size = UDim2.fromScale(1, 0.57),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0.01, 0),
				}),

				-- Разовая покупка силы (без множителей — см. PowerPackConfig/
				-- PowerPackPurchaseHandler). Цена/подпись/грант — из единого
				-- конфига, чтобы менять будущие значения в одном месте.
				PowerBuyButton({
					LayoutOrder = 1,
					Icon = "96772289336842",
					Text = PowerPackConfig.Packs[1].Label,
					Price = PowerPackConfig.Packs[1].Price,
					OnActivated = function()
						onPowerPackActivated(1)
					end,
				}),
				PowerBuyButton({
					LayoutOrder = 2,
					Icon = "96772289336842",
					Text = PowerPackConfig.Packs[2].Label,
					Price = PowerPackConfig.Packs[2].Price,
					OnActivated = function()
						onPowerPackActivated(2)
					end,
				}),
				PowerBuyButton({
					LayoutOrder = 3,
					Icon = "96772289336842",
					Text = PowerPackConfig.Packs[3].Label,
					Price = PowerPackConfig.Packs[3].Price,
					OnActivated = function()
						onPowerPackActivated(3)
					end,
				}),
			}),
		}),
	})
end

return HUD
