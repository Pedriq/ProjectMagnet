local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local sfx = require(ReplicatedStorage.ClientSource.sfx)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local source = vide.source
local spring = vide.spring
local effect = vide.effect
local untrack = vide.untrack
local cleanup = vide.cleanup

--[[
	CarryMeter — заполненность инвентаря переноски (левый нижний угол HUD,
	вместо простой строки «count / capacity»).

	  [icon] 240 / 300            +12
	         [██████████████░░░░]

	  * полоска заполнения: зелёная -> жёлтая -> красная по мере заполнения;
	  * руда добавилась — строка «подпрыгивает», рядом всплывает «+N» (суммируется
	    за короткое окно, чтобы поток кусочков не спамил подписями);
	  * от NEAR_FULL и выше — мягкая пульсация красной обводки (цикл подключён
	    только пока инвентарь почти полон, иначе никакой работы каждый кадр);
	  * инвентарь опустел (сейв на базе / чекпоинт / выгрузка в пресс) — зелёная
	    вспышка, «SAVED!» и полоска плавно стекает в ноль.

	Всё от Data.carryCount / Data.carryCapacity (PlayerManagerService.CarryInventoryChanged).
]]

export type Props = {
	LayoutOrder: number?,
}

local ICON = "rbxassetid://15507675979"
local HEIGHT = 46
local ICON_SIZE = 26

-- руда = металлолом: медь -> предупреждение -> опасность (язык цвета UI.theme)
local GREEN = Theme.CopperBright -- «+N», «SAVED!», полоска на малом заполнении
local YELLOW = Theme.Warning
local RED = Theme.Danger
local TEXT_COLOR = Theme.Text
local BG_COLOR = Theme.Steel800

local NEAR_FULL = 0.8 -- с этой доли — пульсация и красный текст
local GAIN_MERGE_TIME = 0.35 -- «+N» подряд в этом окне складываются в одну подпись

-- фон и чёрная обводка гаснут к правому краю
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.55, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local function fillColor(fraction: number): Color3
	if fraction < 0.6 then
		return GREEN:Lerp(YELLOW, fraction / 0.6)
	end
	return YELLOW:Lerp(RED, math.clamp((fraction - 0.6) / 0.4, 0, 1))
end

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 1.5,
		Color = Color3.new(0, 0, 0),
	})
end

local function CarryMeter(props: Props)
	local function fraction(): number
		local capacity = math.max(Data.carryCapacity(), 1)
		return math.clamp(Data.carryCount() / capacity, 0, 1)
	end

	local shownFraction = spring(fraction, 0.25, 0.85)

	-- элементы, которые анимируем твинами
	local scale = create("UIScale")({ Scale = 1 }) :: UIScale
	local glowStroke = create("UIStroke")({
		Thickness = 2,
		Color = RED,
		Transparency = 1,
	}) :: UIStroke
	-- пульсация — на отдельном оверлее: у одного GuiObject рисуется только один
	-- UIStroke, а у самой рамки — постоянная чёрная обводка (как у StatRow)
	local glow = create("Frame")({
		Name = "Glow",
		ZIndex = 4,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		glowStroke,
	}) :: Frame
	local flash = create("Frame")({
		Name = "Flash",
		ZIndex = 5,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GREEN,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
	}) :: Frame
	local gainLabel = create("TextLabel")({
		Name = "Gain",
		ZIndex = 6,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0, 13),
		Size = UDim2.fromOffset(90, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GREEN,
		TextTransparency = 1,
		Text = "",
		textStroke(),
	}) :: TextLabel
	local gainStroke = gainLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	gainStroke.Transparency = 1

	--=== «+N» и подпрыгивание при добавлении руды =============================
	local gainSum = 0
	local lastGainAt = 0
	local gainToken = 0

	local function showGain(amount: number, text: string?, color: Color3?)
		local now = os.clock()
		if text == nil then
			gainSum = if now - lastGainAt <= GAIN_MERGE_TIME then gainSum + amount else amount
			lastGainAt = now
		end
		gainToken += 1
		local token = gainToken

		gainLabel.Text = text or ("+" .. Format.short(gainSum))
		gainLabel.TextColor3 = color or GREEN
		gainLabel.Position = UDim2.new(1, 6, 0, 13)
		gainLabel.TextTransparency = 0
		gainStroke.Transparency = 0

		local rise = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(gainLabel, rise, { Position = UDim2.new(1, 6, 0, 1) }):Play()
		task.delay(0.45, function()
			if token ~= gainToken then
				return -- пришла новая порция — подпись живёт дальше
			end
			local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(gainLabel, fade, { TextTransparency = 1 }):Play()
			TweenService:Create(gainStroke, fade, { Transparency = 1 }):Play()
		end)
	end

	local function bump(size: number)
		scale.Scale = size
		TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	local function emptiedEffect()
		flash.BackgroundTransparency = 0.35
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		bump(1.12)
		showGain(0, "SAVED!", GREEN)
		sfx.play("Collect", { pitch = 1.25, volume = 0.7 })
	end

	--=== пульсация «почти полон»: цикл живёт только пока fraction >= NEAR_FULL ==
	local pulseConn: RBXScriptConnection? = nil
	local function setPulsing(on: boolean)
		if on and not pulseConn then
			pulseConn = RunService.Heartbeat:Connect(function()
				local wave = 0.5 + 0.5 * math.sin(os.clock() * 5)
				glowStroke.Transparency = 0.15 + 0.6 * (1 - wave)
				glowStroke.Thickness = 2 + wave * 1.5
			end)
		elseif not on and pulseConn then
			pulseConn:Disconnect()
			pulseConn = nil
			TweenService:Create(glowStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end
	end
	cleanup(function()
		setPulsing(false)
	end)

	--=== реакция на изменение инвентаря ====================================
	local prevCount: number? = nil
	effect(function()
		local count = Data.carryCount()
		local ready = Data.ready()
		local frac = fraction()
		untrack(function()
			setPulsing(frac >= NEAR_FULL)
			if not ready then
				return
			end
			if prevCount ~= nil then
				if count > prevCount then
					showGain(count - prevCount)
					bump(if frac >= NEAR_FULL then 1.1 else 1.06)
				elseif count == 0 and prevCount > 0 then
					emptiedEffect()
				end
			end
			prevCount = count
		end)
	end)

	return create("Frame")({
		Name = "CarryMeter",
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(0.75, 0, 0, HEIGHT),
		BackgroundColor3 = BG_COLOR,
		BackgroundTransparency = 0.7,

		scale,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("UIGradient")({ Transparency = FADE }), -- гасит фон
		-- чёрная обводка, гаснет вместе с фоном — как у StatRow (Money / Rebirth)
		create("UIStroke")({
			Thickness = 1.5,
			Color = Color3.new(0, 0, 0),
			create("UIGradient")({ Transparency = FADE }),
		}),

		create("ImageLabel")({
			Name = "Icon",
			Image = ICON,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		}),

		create("TextLabel")({
			Name = "Value",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(ICON_SIZE + 14, 3),
			Size = UDim2.new(1, -(ICON_SIZE + 20), 0, 24),
			Font = Enum.Font.GothamBlack,
			TextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = function()
				return if fraction() >= NEAR_FULL then fillColor(fraction()) else TEXT_COLOR
			end,
			Text = function()
				return Data.carryCount() .. " / " .. Data.carryCapacity()
			end,
			textStroke(),
		}),

		-- полоска заполнения
		create("Frame")({
			Name = "Track",
			Position = UDim2.fromOffset(ICON_SIZE + 14, 31),
			Size = UDim2.new(1, -(ICON_SIZE + 22), 0, 8),
			BackgroundColor3 = Theme.Steel900,
			BorderSizePixel = 0,
			create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
			create("UIStroke")({ Thickness = 1.5 }),

			create("Frame")({
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return fillColor(shownFraction())
				end,
				Size = function()
					return UDim2.fromScale(math.clamp(shownFraction(), 0, 1), 1)
				end,
				create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
				}),
			}),
		}),

		glow,
		flash,
		gainLabel,
	})
end

return CarryMeter
