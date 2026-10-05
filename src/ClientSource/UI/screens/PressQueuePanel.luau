local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)

local create = vide.create
local source = vide.source
local spring = vide.spring
local cleanup = vide.cleanup

--[[
	PressQueuePanel — окно очереди гидравлического пресса (открывается
	ProximityPrompt «Press Queue» на Conveyor, см. PressVisualizer + baseStructures).

	  ┌─ Press Queue ───────────────────────────── [X] ┐
	  │  Lowest rarity is pressed first — remove ...    │
	  │  ◆ Common     ▶ NEXT                x3   [X]    │
	  │    [██████████████░░░░░░░░] 40 / 50             │
	  │  ◆ Rare                                   [X]    │
	  │    [████░░░░░░░░░░░░░░░░░░] 30 / 96             │
	  └─────────────────────────────────────────────────┘

	Строка на каждую руду в прессе (Data.pressOres), в порядке крафта
	(OreConfig.Order — пресс берёт руды по нему, см. PressCraftHandler).
	[X] убирает всю руду этого типа: первый клик — «SURE?», второй в течение
	CONFIRM_TIME — удаление (props.OnRemove -> PressService:RemoveOre).

	Использование:
	  PressQueuePanel({ OnClose = fn, OnRemove = fn(oreId) })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnRemove: (oreId: string) -> (),
}

-- пресс = медь/ржавчина (UI.theme); удаление — опасность
local ROW_COLOR = Theme.Steel700
local TRACK_COLOR = Theme.Steel900
local GOLD = Theme.CopperBright -- NEXT и «x3»
local CONFIRM_COLOR = Theme.Danger
local REMOVE_ICON = "rbxassetid://103344771690872"

local ROW_HEIGHT = 66
local REMOVE_SIZE = 38
local CONFIRM_TIME = 2.5

local function weightOf(oreId: string): number
	return Data.pressOres()[oreId] or 0
end

-- Та же логика, что PressCraftHandler.findCraftableOre: сначала руда, которой
-- хватает на целый предмет, иначе — первый остаток.
local function nextOreId(): string?
	local ores = Data.pressOres()
	for _, oreId in ipairs(OreConfig.Order) do
		local ore = OreConfig.Get(oreId)
		local items = ore and TreasuresConfig[ore.Rarity]
		if (ores[oreId] or 0) >= PressConfig.GetWeightPerItem(oreId) and items and #items > 0 then
			return oreId
		end
	end
	for _, oreId in ipairs(OreConfig.Order) do
		if (ores[oreId] or 0) > 0 then
			return oreId
		end
	end
	return nil
end

local function isEmpty(): boolean
	for _, weight in pairs(Data.pressOres()) do
		if weight > 0 then
			return false
		end
	end
	return true
end

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 2,
		Color = Color3.new(0, 0, 0),
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function OreRow(oreId: string, order: number, onRemove: (string) -> ())
	local ore = OreConfig.Get(oreId)
	local color = RarityColors.get(ore and ore.Rarity or oreId)
	local perItem = PressConfig.GetWeightPerItem(oreId)

	local function weight()
		return weightOf(oreId)
	end
	local function queued()
		return math.floor(weight() / perItem)
	end
	local function isNext()
		return nextOreId() == oreId
	end
	-- целые предметы есть — бар полон (готово к крафту), иначе прогресс остатка
	local fraction = spring(function()
		return if queued() > 0 then 1 else math.clamp((weight() % perItem) / perItem, 0, 1)
	end, 0.25, 1)

	local confirming = source(false)
	local confirmToken = 0
	local hovered = source(false)
	local removeScale = spring(function()
		return (if hovered() then 1.12 else 1) * (if confirming() then 1.08 else 1)
	end, 0.15, 0.6)

	cleanup(function()
		confirmToken += 1
	end)

	return create("Frame")({
		Name = oreId,
		LayoutOrder = order,
		Visible = function()
			return weight() > 0
		end,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		BackgroundColor3 = ROW_COLOR,

		create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
		create("UIGradient")({
			Color = ColorSequence.new(ROW_COLOR:Lerp(color, 0.28), ROW_COLOR),
		}),
		create("UIStroke")({
			Color = function()
				return if isNext() then GOLD else color
			end,
			Thickness = function()
				return if isNext() then 3 else 2
			end,
			Transparency = function()
				return if isNext() then 0 else 0.55
			end,
		}),

		-- «самоцвет» руды
		create("Frame")({
			Name = "Chip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 28, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
			Rotation = 45,
			BackgroundColor3 = color,
			create("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			create("UIStroke")({ Thickness = 2 }),
			create("UIGradient")({
				Rotation = 45,
				Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.35), color:Lerp(Color3.new(0, 0, 0), 0.35)),
			}),
		}),

		create("TextLabel")({
			Name = "OreName",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(54, 6),
			Size = UDim2.new(0.45, -54, 0, 24),
			Font = Enum.Font.GothamBlack,
			TextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color,
			Text = oreId,
			textStroke(),
		}),

		create("TextLabel")({
			Name = "Next",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0.45, 0, 0, 9),
			Size = UDim2.fromOffset(80, 18),
			Font = Enum.Font.GothamBlack,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = GOLD,
			Text = "▶ NEXT",
			Visible = isNext,
			textStroke(1.5),
		}),

		-- справа сверху: «x3» (целых предметов в очереди) или «SURE?» при подтверждении
		create("TextLabel")({
			Name = "Count",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(REMOVE_SIZE + 18), 0, 6),
			Size = UDim2.fromOffset(90, 24),
			Font = Enum.Font.GothamBlack,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = function()
				return if confirming() then CONFIRM_COLOR else GOLD
			end,
			Text = function()
				if confirming() then
					return "SURE?"
				end
				return if queued() > 0 then "x" .. queued() else ""
			end,
			textStroke(),
		}),

		-- прогресс до следующего предмета
		create("Frame")({
			Name = "Track",
			Position = UDim2.fromOffset(54, 36),
			Size = UDim2.new(1, -(54 + REMOVE_SIZE + 18), 0, 20),
			BackgroundColor3 = TRACK_COLOR,
			ClipsDescendants = true,
			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("UIStroke")({ Thickness = 1.5 }),

			create("Frame")({
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Size = function()
					return UDim2.fromScale(fraction(), 1)
				end,
				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.55), color),
				}),
			}),

			create("TextLabel")({
				Name = "Amount",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 2,
				Font = Enum.Font.GothamBlack,
				TextSize = 14,
				TextColor3 = Color3.new(1, 1, 1),
				Text = function()
					local w = weight()
					local shown = if queued() > 0 then w else w % perItem
					return string.format("%d / %d", math.floor(shown), perItem)
				end,
				textStroke(1.5),
			}),
		}),

		-- [X] убрать руду (та же картинка, что у закрытия окна)
		create("ImageButton")({
			Name = "Remove",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -(REMOVE_SIZE / 2 + 10), 0.5, 0),
			Size = function()
				local s = REMOVE_SIZE * removeScale()
				return UDim2.fromOffset(s, s)
			end,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = REMOVE_ICON,
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = function()
				return if confirming() then CONFIRM_COLOR else Color3.new(1, 1, 1)
			end,

			MouseEnter = function()
				hovered(true)
				sfx.play("HoverUI")
			end,
			MouseLeave = function()
				hovered(false)
			end,
			Activated = function()
				if not confirming() then
					-- первый клик — подтверждение
					sfx.play("ClickUI")
					confirming(true)
					confirmToken += 1
					local token = confirmToken
					task.delay(CONFIRM_TIME, function()
						if confirmToken == token then
							confirming(false)
						end
					end)
					return
				end
				confirmToken += 1
				confirming(false)
				sfx.play("ClickUI", { pitch = 0.7 })
				onRemove(oreId)
			end,
		}),
	})
end

local function PressQueuePanel(props: Props)
	return function()
		local rows = {}
		for i, oreId in ipairs(OreConfig.Order) do
			table.insert(rows, OreRow(oreId, i + 1, props.OnRemove))
		end

		return Panel({
			ZIndex = 10,
			Size = UDim2.fromOffset(560, 520),
			OnClose = props.OnClose,

			Title = "Press Queue",
			TitleColor = Theme.titleColor("Copper"),
			BodyColor = Theme.bodyColor("Copper"),
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
				VerticalScrollBarInset = Enum.ScrollBarInset.Always,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Vertical,
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 8),
				}),
				create("UIPadding")({
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),

				-- подсказка, зачем удалять руду
				create("TextLabel")({
					Name = "Hint",
					LayoutOrder = 0,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 22),
					Font = Enum.Font.GothamBold,
					TextSize = 15,
					TextColor3 = Theme.TextMuted,
					Text = "Lowest rarity is pressed first — remove cheap ore to skip it.",
					TextWrapped = true,
					textStroke(1.5),
				}),

				create("TextLabel")({
					Name = "Empty",
					LayoutOrder = 1,
					Visible = isEmpty,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 60),
					Font = Enum.Font.GothamBlack,
					TextSize = 22,
					TextColor3 = Theme.TextMuted,
					Text = "The press is empty.\nUnload ore to start crafting!",
					textStroke(),
				}),

				table.unpack(rows),
			}),
		})
	end
end

return PressQueuePanel
