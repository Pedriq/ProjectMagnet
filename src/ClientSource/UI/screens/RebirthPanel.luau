local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
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
	  │        Rebirth resets your Strength!        │
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

local RED = Color3.fromRGB(255, 64, 72)
local STRENGTH = Color3.fromRGB(255, 208, 1)
local MONEY = Color3.fromRGB(56, 240, 72)
local GOLD = Color3.fromRGB(255, 198, 56)

local perStr = RebirthConfig.StrengthMultiplierPerRebirth
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
		return fmtMult(1 + Data.rebirths() * perStr)
	end
	local function strTo()
		return fmtMult(1 + (Data.rebirths() + 1) * perStr)
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
			TitleColor = RED,
			TitleTransparency = 0, -- не разбавлять красный тёмным телом позади
			BodyColor = Color3.fromRGB(22, 14, 15),
			BodyTransparency = 0.7,
			StrokeColor = Color3.fromRGB(0, 0, 0),
			TitleImage = "rbxassetid://137638295200351",
			TitleImageTransparency = 0.6,
			StrokeThickness = 3,

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
				Color = STRENGTH,
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
				TextColor3 = Color3.fromRGB(245, 245, 240),
				Text = "Rebirth resets your Strength!",

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
				BackgroundColor3 = Color3.fromRGB(58, 44, 20),
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
					BackgroundColor3 = GOLD,

					create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
					create("UIGradient")({
						Rotation = 90,
						Color = ColorSequence.new(Color3.fromRGB(255, 214, 92), Color3.fromRGB(236, 166, 28)),
					}),
					create("ImageLabel")({
						Name = "Texture",
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
					TextColor3 = Color3.fromRGB(250, 250, 245),
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
					Color = RED,
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
					Color = GOLD,
					TextColor = Color3.fromRGB(255, 255, 255),
					TextureTransparency = 0.66,
					OnActivated = props.OnSkip,
				}),
			}),
		})
	end
end

return RebirthPanel
