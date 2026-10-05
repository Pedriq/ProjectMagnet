local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local vide = require(ReplicatedStorage.Packages.Vide)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)

local Data = require(ReplicatedStorage.ClientSource.UI.data)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local source = vide.source
local effect = vide.effect
local untrack = vide.untrack
local cleanup = vide.cleanup

--[[
	SavedOreMeter — сколько руды игрок СОХРАНИЛ (profile.Ores), отдельно от
	руды в прессе (profile.Press.Ores) и от несомой (CarryMeter). Левый нижний
	угол HUD, сразу над CarryMeter.

	  [icon] 1.2K             +240

	  * сейв рюкзака на базе (PlayerOreInventory:SaveToProfile) — число
	    «накручивается» вверх, медная вспышка и «+N»;
	  * выгрузка в пресс (PlayerOreInventory:TakeAll обнуляет profile.Ores) —
	    число стекает вниз, «-N» синим.

	Всё от Data.ores (ProfileService.UpdateSpecificData, путь Ores/<oreId>).
	Сервер шлёт по событию на каждую руду — изменения в коротком окне
	складываются в одну подпись.
]]

export type Props = {
	LayoutOrder: number?,
}

local ICON = "rbxassetid://75588119022884"
local HEIGHT = 46
local ICON_SIZE = 34 -- как у Money (StatRow Large)

local GAIN_COLOR = Theme.CopperBright -- руда/металлолом (см. UI.theme)
local LOSS_COLOR = Theme.ElectricBright
local TEXT_COLOR = Theme.Text
local BG_COLOR = Theme.Steel800

local ROLL_SPEED = 10 -- скорость «накрутки» числа (доля разницы в секунду)
local CHANGE_MERGE_TIME = 0.35 -- изменения подряд в этом окне — одна подпись

-- фон и обводка гаснут к правому краю (как у CarryMeter)
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.55, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local function textStroke(thickness: number?)
	return create("UIStroke")({
		Thickness = thickness or 1.5,
		Color = Color3.new(0, 0, 0),
	})
end

local function totalSaved(): number
	local total = 0
	for _, weight in pairs(Data.ores()) do
		total += weight
	end
	return total
end

local function SavedOreMeter(props: Props)
	-- показываемое значение догоняет настоящее; цикл подключён только пока догоняет
	local shown = source(totalSaved())
	local rollConn: RBXScriptConnection? = nil

	local function stopRoll()
		if rollConn then
			rollConn:Disconnect()
			rollConn = nil
		end
	end
	local function startRoll()
		if rollConn then
			return
		end
		rollConn = RunService.Heartbeat:Connect(function(dt)
			local target = totalSaved()
			local current = shown()
			local nextValue = current + (target - current) * math.min(dt * ROLL_SPEED, 1)
			if math.abs(target - nextValue) < 0.5 then
				shown(target)
				stopRoll()
			else
				shown(nextValue)
			end
		end)
	end
	cleanup(stopRoll)

	-- элементы, которые анимируем твинами
	local scale = create("UIScale")({ Scale = 1 }) :: UIScale
	local flash = create("Frame")({
		Name = "Flash",
		ZIndex = 5,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = GAIN_COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
	}) :: Frame
	local changeLabel = create("TextLabel")({
		Name = "Change",
		ZIndex = 6,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 6, 0, 13),
		Size = UDim2.fromOffset(90, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = GAIN_COLOR,
		TextTransparency = 1,
		Text = "",
		textStroke(),
	}) :: TextLabel
	local changeStroke = changeLabel:FindFirstChildOfClass("UIStroke") :: UIStroke
	changeStroke.Transparency = 1

	--=== «+N» / «-N» ========================================================
	local changeSum = 0
	local lastChangeAt = 0
	local changeToken = 0

	local function showChange(delta: number)
		local now = os.clock()
		-- смена знака — новая подпись, а не «+240» минус «240» = «0»
		local merge = now - lastChangeAt <= CHANGE_MERGE_TIME and (changeSum > 0) == (delta > 0)
		changeSum = if merge then changeSum + delta else delta
		lastChangeAt = now
		changeToken += 1
		local token = changeToken

		local gain = changeSum > 0
		changeLabel.Text = (if gain then "+" else "-") .. Format.short(math.abs(changeSum))
		changeLabel.TextColor3 = if gain then GAIN_COLOR else LOSS_COLOR
		changeLabel.Position = UDim2.new(1, 6, 0, 13)
		changeLabel.TextTransparency = 0
		changeStroke.Transparency = 0

		local rise = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(changeLabel, rise, { Position = UDim2.new(1, 6, 0, if gain then 1 else 25) }):Play()
		task.delay(0.6, function()
			if token ~= changeToken then
				return -- пришла новая порция — подпись живёт дальше
			end
			local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(changeLabel, fade, { TextTransparency = 1 }):Play()
			TweenService:Create(changeStroke, fade, { Transparency = 1 }):Play()
		end)
	end

	local function pulse(gain: boolean)
		flash.BackgroundColor3 = if gain then GAIN_COLOR else LOSS_COLOR
		flash.BackgroundTransparency = if gain then 0.35 else 0.55
		TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()

		scale.Scale = if gain then 1.1 else 0.94
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	--=== реакция на изменение сохранённой руды ================================
	local prevTotal: number? = nil
	effect(function()
		local total = totalSaved()
		local ready = Data.ready()
		untrack(function()
			if not ready then
				shown(total)
				return
			end
			-- первый снапшот профиля — без анимации
			if prevTotal == nil then
				shown(total)
			elseif total ~= prevTotal then
				showChange(total - prevTotal)
				pulse(total > prevTotal)
				startRoll()
			end
			prevTotal = total
		end)
	end)

	return create("Frame")({
		Name = "SavedOreMeter",
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
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ICON_SIZE + 14, 0.5, 0),
			Size = UDim2.new(1, -(ICON_SIZE + 20), 0, 24),
			Font = Enum.Font.GothamBlack,
			TextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = TEXT_COLOR,
			Text = function()
				return Format.short(math.floor(shown() + 0.5))
			end,
			textStroke(),
		}),

		flash,
		changeLabel,
	})
end

return SavedOreMeter
