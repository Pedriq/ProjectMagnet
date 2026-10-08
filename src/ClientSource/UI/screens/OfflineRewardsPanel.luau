local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Offline = require(ReplicatedStorage.ClientSource.UI.offline)
local viewportScale = require(ReplicatedStorage.ClientSource.UI.viewportScale)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local source = vide.source
local spring = vide.spring
local show = vide.show

--[[
	OfflineRewardsPanel — окно «Welcome Back!» с наградой за время вне игры.

	  ┌─ Welcome Back! ─────────────────────── [✕] ┐
	  │  Press Earnings                   $1.2M     │
	  │  Magnetism                        +3.4K     │
	  │             [      Claim      ]             │
	  └─────────────────────────────────────────────┘

	Яркая, насыщенная палитра (Theme.Offline*, Money/Electric Bright) — окно должно сразу бросаться в глаза.
	Длительность отсутствия в окне НЕ показывается. Награду считает и выдаёт сервер (OfflineService);
	[✕] окно просто закрывает — награда остаётся и покажется при следующем заходе.
]]

local BODY_COLOR = Theme.Steel800:Lerp(Theme.Offline, 0.16)

local function textStroke()
	return create("UIStroke")({
		Thickness = 2,
		Color = Color3.new(0, 0, 0),
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Строка «подпись — значение»: плашка, подкрашенная цветом награды, яркая обводка и цветная кромка слева.
local function Row(order: number, label: string, value: string, accent: Color3, tint: Color3)
	return create("Frame")({
		Name = label,
		LayoutOrder = order,
		Size = UDim2.new(1, -24, 0, 62),
		BackgroundColor3 = tint,
		BackgroundTransparency = 0,

		create("UICorner")({ CornerRadius = UDim.new(0, 10) }),
		create("UIStroke")({
			Thickness = 2.5,
			Color = accent,
			Transparency = 0.15,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		create("UIGradient")({
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.72, 0.72, 0.72)),
		}),

		create("Frame")({
			Name = "Accent",
			Size = UDim2.new(0, 6, 1, -14),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
		}),
		create("TextLabel")({
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(0.4, -24, 1, 0),
			Font = Enum.Font.GothamBold,
			TextSize = 19,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = label,
		}),
		create("TextLabel")({
			Name = "Value",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.6, -14, 1, 0),
			Font = Enum.Font.GothamBlack,
			TextSize = 32,
			TextColor3 = accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = value,

			textStroke(),
		}),
	})
end

local function OfflineRewardsPanel()
	local guiScale = viewportScale()
	local appear = source(0)
	task.defer(appear, 1)
	local popScale = spring(function()
		return 0.88 + 0.12 * appear()
	end, 0.3)

	return show(function()
		return Offline.reward() ~= nil
	end, function()
		-- награда не меняется, пока окно открыто (после Claim оно закрывается)
		local reward = Offline.reward()
		local hasMoney = reward.Money ~= nil and reward.Money ~= "0"
		local hasMagnetism = reward.Magnetism ~= nil and reward.Magnetism ~= "0"

		return create("Frame")({
			Name = "OfflineRewards",
			Size = function()
				local s = guiScale()
				return UDim2.fromScale(1 / s, 1 / s)
			end,
			-- без затемнения, как у остальных панелей: фон размывает BlurEffect (HUD). Active — клики не уходят в мир.
			BackgroundTransparency = 1,
			Active = true,

			create("UIScale")({ Scale = guiScale }),

			create("Frame")({
				Name = "Pop",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,

				create("UIScale")({ Scale = popScale }),

				Panel({
					ZIndex = 10,
					Size = UDim2.fromOffset(460, 362),
					OnClose = Offline.dismiss,

					Title = "Welcome Back!",
					TitleColor = Theme.Offline,
					TitleTextColor = Color3.new(1, 1, 1),
					TitleTransparency = 0,
					BodyColor = BODY_COLOR,
					BodyTransparency = 0.05,
					StrokeColor = Theme.OfflineBright,
					TitleImage = Theme.PanelTitleTexture,
					TitleImageTransparency = Theme.PanelTitleTextureTransparency,
					StrokeThickness = Theme.PanelStrokeThickness,
					CloseColor = Theme.Danger,

					List = false,

					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 14),
					}),

					Row(1, "Press Earnings", "$" .. Format.short(reward.Money or "0"), Theme.MoneyBright, Theme.MoneyDeep),
					Row(
						2,
						"Magnetism",
						"+" .. Format.short(reward.Magnetism or "0"),
						Theme.ElectricBright,
						Theme.ElectricDeep
					),

					WideButton({
						LayoutOrder = 3,
						Text = "Claim",
						Size = UDim2.fromOffset(220, 58),
						TextSize = 30,
						Color = Theme.Money,
						Disabled = not (hasMoney or hasMagnetism),
						OnActivated = Offline.claim,
					}),
				}),
			}),
		})
	end)
end

return OfflineRewardsPanel
