local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local MultiplierRow = require(ReplicatedStorage.ClientSource.UI.components.MultiplierRow)
local WideButton = require(ReplicatedStorage.ClientSource.UI.components.WideButton)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)

local create = vide.create

local asset = Format.asset

--[[
	RebirthPanel — окно ребёрса (по макету).

	  ┌─ Rebirth ───────────────────────────── [✕] ┐
	  │  [ x8.5 ]  ▶  [ x9 ]        (сила, оранж.)  │
	  │  [ x4   ]  ▶  [ x4.2 ]      (деньги, зел.)  │
	  │        Rebirth resets your Magnetism!        │
	  │  ┌───────── Level 7 / 10 ───────────────┐   │  ← полоса прогресса уровня
	  │  [   Rebirth   ]        [    Skip    ]       │
	  └────────────────────────────────────────────┘

	Множители считаются как на сервере (RebirthHandler): 1 + rebirths * perRebirth.
	Кнопка Rebirth недоступна, пока level < RebirthConfig.RequiredLevelForRebirth(rebirths).

	ИКОНКИ в пилюлях/тайтле пока не заведены — добавятся позже через props.

	Использование: RebirthPanel({ OnClose = fn, OnRebirth = fn?, OnSkip = fn? })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnRebirth: (() -> ())?, -- TODO: серверного ремоута для ребёрса ещё нет
	OnSkip: (() -> ())?,
}

-- язык цвета UI.theme: сила (магнит) — синий, деньги — зелёный, ребёрс — фиолетовый
local MAGNETISM = Theme.Electric
local MONEY = Theme.Money

local perMagnetism = RebirthConfig.MagnetismMultiplierPerRebirth
local perCash = RebirthConfig.CashMultiplierPerRebirth

local function reqLevel(): number
	return RebirthConfig.RequiredLevelForRebirth(Data.rebirths())
end

local function fmtMult(n: number): string
	local s = string.format("%.1f", n)
	if string.sub(s, -2) == ".0" then
		s = string.sub(s, 1, -3)
	end
	return "x" .. s
end

local function RebirthPanel(props: Props)
	local function strFrom()
		return fmtMult(1 + Data.rebirths() * perMagnetism)
	end
	local function strTo()
		return fmtMult(1 + (Data.rebirths() + 1) * perMagnetism)
	end
	local function cashFrom()
		return fmtMult(1 + Data.rebirths() * perCash)
	end
	local function cashTo()
		return fmtMult(1 + (Data.rebirths() + 1) * perCash)
	end

	local function canRebirth(): boolean
		return Data.level() >= reqLevel()
	end
	local function levelProgress(): number
		return math.clamp(Data.level() / reqLevel(), 0, 1)
	end
	local function levelText(): string
		return `Level {Data.level()} / {reqLevel()}`
	end

	return function()
		return Panel({
			ZIndex = 10,
			Icon = "rbxassetid://80993270685237",
			Size = UDim2.fromOffset(520, 460),
			OnClose = props.OnClose,

			Title = "Rebirth",
			TitleColor = Theme.titleColor("Rebirth"),
			TitleTransparency = 0, -- не разбавлять красный тёмным телом позади
			BodyColor = Theme.bodyColor("Rebirth"),
			BodyTransparency = Theme.PanelBodyTransparency,
			StrokeColor = Theme.Outline,
			TitleImage = Theme.PanelTitleTexture,
			TitleImageTransparency = Theme.PanelTitleTextureTransparency,
			StrokeThickness = Theme.PanelStrokeThickness,

			List = false,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 16),
			}),

			MultiplierRow({
				LayoutOrder = 1,
				Color = MAGNETISM,
				From = strFrom,
				To = strTo,
				Icon = "96772289336842",
			}),
			MultiplierRow({
				LayoutOrder = 2,
				Color = MONEY,
				From = cashFrom,
				To = cashTo,
				Icon = "117287387544386",
			}),

			create("TextLabel")({
				Name = "Note",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				TextSize = 20,
				TextColor3 = Theme.Warning,
				Text = "Rebirth resets your Magnetism!",

				create("UIStroke")({
					Thickness = 2,
					Color = Color3.new(0, 0, 0),
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			}),

			--== полоса прогресса уровня =====================================
			create("Frame")({
				Name = "LevelBar",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = Theme.Steel900,
				ClipsDescendants = true,

				create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
				create("UIStroke")({
					Thickness = 3,
					Color = Color3.new(0, 0, 0),
					Transparency = 0.1,
				}),

				create("Frame")({
					Name = "Fill",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = function()
						return UDim2.new(levelProgress(), 0, 1, 0)
					end,
					-- тот же градиент синий -> красный, что у полосы уровня в HUD:
					-- слой на всю ширину полосы, заполнение его «открывает»
					BackgroundTransparency = 1,
					ClipsDescendants = true,

					create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					create("Frame")({
						Name = "GradientSpan",
						BorderSizePixel = 0,
						BackgroundColor3 = Color3.new(1, 1, 1),
						Size = function()
							return UDim2.fromScale(1 / math.max(levelProgress(), 0.001), 1)
						end,
						create("UIGradient")({ Color = Theme.LEVEL_GRADIENT }),
					}),
					create("ImageLabel")({
						Name = "Texture",
						ZIndex = 2, -- поверх GradientSpan
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Image = asset("137638295200351"),
						ImageTransparency = 0.45,
						ScaleType = Enum.ScaleType.Tile,
						TileSize = UDim2.fromOffset(46, 46),
					}),
				}),

				create("TextLabel")({
					Name = "Label",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Font = Enum.Font.GothamBlack,
					TextSize = 22,
					TextColor3 = Theme.Text,
					Text = levelText,

					create("UIStroke")({
						Thickness = 2,
						Color = Color3.new(0, 0, 0),
						LineJoinMode = Enum.LineJoinMode.Round,
					}),
				}),
			}),

			--== кнопки =====================================================
			create("Frame")({
				Name = "Buttons",
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 64),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 26),
				}),

				WideButton({
					LayoutOrder = 1,
					Text = "Rebirth",
					Size = UDim2.fromOffset(200, 58),
					Color = Theme.ButtonRebirth,
					TextureTransparency = 0.5,
					Disabled = function()
						return not canRebirth()
					end,
					OnActivated = props.OnRebirth,
				}),
				WideButton({
					LayoutOrder = 2,
					Text = "Skip",
					Size = UDim2.fromOffset(176, 58),
					Color = Theme.ButtonGold,
					TextColor = Theme.Text,
					TextureTransparency = 0.66,
					OnActivated = props.OnSkip,
				}),
			}),
		})
	end
end

return RebirthPanel
