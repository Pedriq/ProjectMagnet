local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local PressConfig = require(ReplicatedStorage.SharedSource.Datas.PressConfig)
local PressMergeConfig = require(ReplicatedStorage.SharedSource.Datas.PressMergeConfig)
local RarityColors = require(ReplicatedStorage.SharedSource.Datas.RarityColors)
local TreasuresConfig = require(ReplicatedStorage.SharedSource.Datas.TreasuresConfig)

local create = vide.create
local source = vide.source
local spring = vide.spring
local cleanup = vide.cleanup
local effect = vide.effect
local untrack = vide.untrack

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

	Ore Merge (PressMergeConfig): панель Ore Merge показывает ratio и до какого тира можно
	объединять; сам merge — касанием площадки Merge у пресса (PressMergeHandler). В строке
	руды при merge — вспышка и «+N Руда».

	Использование:
	  PressQueuePanel({ OnClose = fn, OnRemove = fn(oreId) })
	возвращает компонент-тезис () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnRemove: (oreId: string) -> (),
}

-- пресс = холодная «нержавеющая сталь» (UI.theme, Teal) — оба окна пресса одного цвета
local ROW_COLOR = Theme.Steel700
local TRACK_COLOR = Theme.Steel900
local GOLD = Theme.CopperBright -- NEXT и «x3»
local CONFIRM_COLOR = Theme.Danger
local TITLE_ICON = "rbxassetid://136449007381728" -- иконка в тайтле окна
local REMOVE_ICON ="rbxassetid://103344771690872"

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

-- ratio/рекорд тира из Data — те же, что считает сервер (PressMergeConfig.Plan)
local function mergeRatio(): number
	return PressMergeConfig.GetRatio(Data.pressMergeLevel())
end

local function highestIndex(): number
	return PressMergeConfig.HighestIndex(Data.pressHighestOre(), Data.pressOres())
end

-- Эффект merge на строке результата: мягкая вспышка по строке + «+2 Rare», всплывающее вверх.
local function playMergeFx(row: Frame, color: Color3, text: string)
	local flash = Instance.new("Frame")
	flash.Name = "MergeFlash"
	flash.ZIndex = 8
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(color, 0.25)
	flash.BackgroundTransparency = 0.4
	flash.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = flash
	flash.Parent = row
	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()

	local popup = Instance.new("TextLabel")
	popup.Name = "MergePopup"
	popup.ZIndex = 9
	popup.BackgroundTransparency = 1
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.Size = UDim2.fromOffset(200, 28)
	popup.Font = Enum.Font.GothamBlack
	popup.TextSize = 22
	popup.TextColor3 = Color3.new(1, 1, 1):Lerp(color, 0.35)
	popup.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = popup
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = popup
	popup.Parent = row

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, rise, { Position = UDim2.new(0.5, 0, 0.5, -26) }):Play()
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6)
	TweenService:Create(popup, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(1.1, function()
		flash:Destroy()
		popup:Destroy()
	end)
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

	local row = create("Frame")({
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
	}) :: Frame

	-- эффект merge на строке, КУДА пришла руда (событие приходит от сервера после подтверждения);
	-- id уже показанного события запоминаем, чтобы открытие окна не проигрывало старое
	local lastEvent = untrack(Data.mergeEvent)
	local lastId = lastEvent and lastEvent.Id or 0
	effect(function()
		local event = Data.mergeEvent()
		if not event or event.Id == lastId then
			return
		end
		lastId = event.Id
		untrack(function()
			for _, step in ipairs(event.Steps) do
				if step.To == oreId then
					playMergeFx(row, color, `+{step.Groups} {oreId}`)
				end
			end
		end)
	end)

	return row
end

-- Панель Ore Merge над списком: ratio и до какого тира можно (сам merge — площадка Merge у пресса).
local function MergeBar()
	return create("Frame")({
		Name = "MergeBar",
		LayoutOrder = 0,
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = ROW_COLOR,

		create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
		create("UIStroke")({ Color = Theme.Teal, Thickness = 2, Transparency = 0.45 }),

		create("TextLabel")({
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -28, 0, 22),
			Font = Enum.Font.GothamBlack,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TealBright,
			Text = function()
				return "Ore Merge  " .. PressMergeConfig.RatioText(Data.pressMergeLevel())
			end,
			textStroke(),
		}),
		create("TextLabel")({
			Name = "Sub",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 29),
			Size = UDim2.new(1, -28, 0, 16),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.TextMuted,
			Text = function()
				return "Up to " .. OreConfig.Order[highestIndex()] .. " · merge at the press · improve in Press Upgrade"
			end,
			textStroke(1.5),
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
			Icon = TITLE_ICON,
			TitleColor = Theme.titleColor("Teal"),
			BodyColor = Theme.bodyColor("Teal"),
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
					LayoutOrder = -1,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -8, 0, 22),
					Font = Enum.Font.GothamBold,
					TextSize = 15,
					TextColor3 = Theme.TextMuted,
					Text = "Lowest rarity is pressed first — merge cheap ore up at the press, or remove it to skip.",
					TextWrapped = true,
					textStroke(1.5),
				}),

				MergeBar(),

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
