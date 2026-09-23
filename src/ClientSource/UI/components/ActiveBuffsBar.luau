local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)
local BuffConfig = require(ReplicatedStorage.SharedSource.Datas.BuffConfig)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local BuffChip = require(ReplicatedStorage.ClientSource.UI.components.BuffChip)

local create = vide.create
local source = vide.source
local show = vide.show
local cleanup = vide.cleanup

--[[
	ActiveBuffsBar — активные временные баффы (Data.buffs, см. BuffHandler на
	сервере) в правом нижнем углу экрана, в ряд ("полосочка").

	Обратный отсчёт — на клиенте: считаем сами по workspace:GetServerTimeNow()
	(тот же приём, что TreasureBillboard), без лишних сигналов с сервера — бафф
	просто пропадает из бара сам, когда время вышло.
]]

-- порядок и цвет плиток по типу баффа (те же акценты, что у BoostCard в Shop)
local ORDER = {
	{ Type = "Magnetism", Color = Color3.fromRGB(255, 195, 35) },
	{ Type = "Money", Color = Color3.fromRGB(76, 242, 0) },
}

local function formatTime(seconds: number): string
	seconds = math.max(math.ceil(seconds), 0)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function ActiveBuffsBar()
	local now = source(Workspace:GetServerTimeNow())
	local lastSecond = math.floor(now())

	-- обновляем реактивный источник раз в секунду (не каждый кадр) — этого
	-- достаточно для отображаемого таймера mm:ss.
	local conn = RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		local second = math.floor(t)
		if second ~= lastSecond then
			lastSecond = second
			now(t)
		end
	end)
	cleanup(function()
		conn:Disconnect()
	end)

	local function remaining(buffType: string): number
		local buff = Data.buffs()[buffType]
		if not buff then
			return 0
		end
		return buff.ExpiresAt - now()
	end

	local function isActive(buffType: string): boolean
		return remaining(buffType) > 0
	end

	local chips = {}
	for index, entry in ipairs(ORDER) do
		local buffType = entry.Type
		local icon = BuffConfig.Display[buffType] and BuffConfig.Display[buffType].Icon or ""

		table.insert(
			chips,
			show(function()
				return isActive(buffType)
			end, function()
				return BuffChip({
					LayoutOrder = index,
					Icon = icon,
					Color = entry.Color,
					Multiplier = function()
						local buff = Data.buffs()[buffType]
						return `x{1 + (buff and buff.Bonus or 0)}`
					end,
					TimeLeft = function()
						return formatTime(remaining(buffType))
					end,
				})
			end)
		)
	end

	return create("Frame")({
		Name = "ActiveBuffsBar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(0, 86),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,

		create("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),

		table.unpack(chips),
	})
end

return ActiveBuffsBar
