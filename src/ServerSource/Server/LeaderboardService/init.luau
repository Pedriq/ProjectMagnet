local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local LeaderboardConfig = require(ReplicatedStorage.SharedSource.Datas.LeaderboardConfig)

--[[
	Глобальные (кросс-серверные, через OrderedDataStore) лидерборды по силе и деньгам
	(Stats.Magnetism / Stats.Money — EtNum-строки произвольной точности). Физические доски
	лежат в каждом мире отдельно: World<N>BaseZone.Leaderboards.Magnetism/Money — при
	обновлении топ-100 переписываются ВСЕ такие доски во всех мирах сразу (миров со
	временем станет больше — World2BaseZone, World3BaseZone и т.д., без правок кода).

	Т.к. Stats.Magnetism/Money могут выходить далеко за пределы double/int64, для
	OrderedDataStore значение кодируется через EtNum.lbencode/lbdecode (см. eternitynum2,
	функции специально для лидербордов), а не напрямую как число.

	Наполняется только новыми входами/выходами начиная с этого обновления — игроки,
	заходившие раньше и больше не заходящие, в топ ретроактивно не подтягиваются.
]]
local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
})

local ProfileService

local STATS = {
	{
		key = "Magnetism",
		store = DataStoreService:GetOrderedDataStore("GlobalMagnetism"),
		path = { "Stats", "Magnetism" },
		title = "TOP-100 · MAGNETISM",
		rowColor = Color3.fromRGB(85, 27, 35),
	},
	{
		key = "Money",
		store = DataStoreService:GetOrderedDataStore("GlobalMoney"),
		path = { "Stats", "Money" },
		title = "TOP-100 · MONEY",
		rowColor = Color3.fromRGB(31, 95, 55),
	},
}

-- Модели-доски лежат в каждом мире по одному и тому же относительному пути:
-- World<N>BaseZone.Leaderboards.<statKey> (подтверждено реальным именем в Workspace,
-- комментарий в baseStructures.luau про "BazeZone" — опечатка, не ориентируйся на него).
local WORLD_ZONE_PATTERN = "^World%d+BaseZone$"

local BARLOW_BOLD = Font.new("rbxasset://fonts/families/Barlow.json", Enum.FontWeight.Bold)

local ROW_HEIGHT = 34
local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 215, 0),
	[2] = Color3.fromRGB(200, 200, 200),
	[3] = Color3.fromRGB(205, 127, 50),
}

local function getStatValue(profileData, path)
	local value = profileData
	for i = 1, #path do
		value = value[path[i]]
		if value == nil then
			return 0
		end
	end
	return value
end

--[[
	@description Пишет текущие Magnetism/Money игрока в оба OrderedDataStore. Вызывается при
	входе/выходе и периодически для тех, кто ещё в игре (см. KnitStart) — не на каждое
	изменение стата (Magnetism/Money меняются на каждый клик), чтобы не упереться в лимиты DataStore.
]]
local lastWritten: { [string]: number } = {} -- [userId .. statKey] = последнее записанное значение

local function syncPlayer(player: Player)
	local _, profileData = ProfileService:GetProfile(player)
	if not profileData then
		return
	end

	local key = tostring(player.UserId)
	for _, stat in ipairs(STATS) do
		local rawValue = getStatValue(profileData, stat.path)
		local encoded = math.floor(EtNum.lbencode(rawValue))
		local cacheKey = key .. stat.key
		if lastWritten[cacheKey] == encoded then
			continue -- с прошлой записи не изменилось — SetAsync не нужен
		end
		local ok, err = pcall(function()
			stat.store:SetAsync(key, encoded)
		end)
		if ok then
			lastWritten[cacheKey] = encoded
		else
			warn(
				("LeaderboardService: не удалось записать %s для %s: %s"):format(
					stat.key,
					player.Name,
					tostring(err)
				)
			)
		end
	end
end

-- Все доски одного стата во всех мирах: World<N>BaseZone.Leaderboards.<statKey>
local function findLeaderboardModels(statKey: string): { Instance }
	local models = {}
	for _, worldZone in ipairs(Workspace:GetChildren()) do
		if worldZone.Name:match(WORLD_ZONE_PATTERN) then
			local leaderboards = worldZone:FindFirstChild("Leaderboards")
			if not leaderboards then
				warn(("LeaderboardService: у %s нет папки Leaderboards"):format(worldZone:GetFullName()))
				continue
			end

			local model = leaderboards:FindFirstChild(statKey)
			if model then
				table.insert(models, model)
			else
				local childNames = {}
				for _, child in ipairs(leaderboards:GetChildren()) do
					table.insert(childNames, child.Name)
				end
				warn(
					("LeaderboardService: в %s нет ребёнка с именем %q (регистр важен), реально внутри: [%s]"):format(
						leaderboards:GetFullName(),
						statKey,
						table.concat(childNames, ", ")
					)
				)
			end
		end
	end
	return models
end

-- Поверхность под SurfaceGui: сама модель, если это BasePart, иначе её "Screen",
-- иначе первый попавшийся BasePart внутри.
local function resolveScreen(model: Instance): BasePart?
	if model:IsA("BasePart") then
		return model
	end

	local screen = model:FindFirstChild("Screen")
	if screen and screen:IsA("BasePart") then
		return screen
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			return inst
		end
	end

	return nil
end

-- Доска строится один раз (SurfaceGui + заголовок + ScrollingFrame под 100 строк),
-- дальше только очищаем и перезаполняем Rows при каждом обновлении.
local function ensureGui(screen: BasePart, title: string): ScrollingFrame
	local existing = screen:FindFirstChild("LeaderboardGui")
	if existing then
		existing.MaxDistance = LeaderboardConfig.RENDER_DISTANCE
		return existing.Root.Rows
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0
	gui.MaxDistance = LeaderboardConfig.RENDER_DISTANCE
	gui.Parent = screen

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = root

	local rootLayout = Instance.new("UIListLayout")
	rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rootLayout.Padding = UDim.new(0.02, 0)
	rootLayout.Parent = root

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.LayoutOrder = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BARLOW_BOLD
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = title
	titleLabel.Parent = root

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.LayoutOrder = 2
	rows.Size = UDim2.new(1, 0, 1, -46)
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.ScrollBarThickness = 6
	rows.CanvasSize = UDim2.new()
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.Parent = root

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0.02, 0)
	rowsLayout.Parent = rows

	return rows
end

local function clearRows(rows: ScrollingFrame)
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createRow(rank: number, name: string, valueText: string, rowColor: Color3): Frame
	local accentColor = RANK_COLORS[rank] or Color3.fromRGB(255, 255, 255)

	local row = Instance.new("Frame")
	row.Name = "Row" .. rank
	row.LayoutOrder = rank
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = rowColor
	row.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, 8)
	rowPadding.PaddingRight = UDim.new(0, 8)
	rowPadding.Parent = row

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0.02, 0)
	rowLayout.Parent = row

	local rankLabel = Instance.new("TextLabel")
	rankLabel.LayoutOrder = 1
	rankLabel.Size = UDim2.new(0, 40, 1, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.FontFace = BARLOW_BOLD
	rankLabel.TextScaled = true
	rankLabel.TextColor3 = accentColor
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.Text = "#" .. rank
	rankLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.LayoutOrder = 2
	nameLabel.Size = UDim2.new(1, -122, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace = BARLOW_BOLD
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = name
	nameLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.LayoutOrder = 3
	valueLabel.Size = UDim2.new(0, 76, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = BARLOW_BOLD
	valueLabel.TextScaled = true
	valueLabel.TextColor3 = accentColor
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = valueText
	valueLabel.Parent = row

	return row
end

local function fetchTop(stat)
	local ok, pagesOrErr = pcall(function()
		return stat.store:GetSortedAsync(false, LeaderboardConfig.TOP_COUNT)
	end)
	if not ok then
		warn(("LeaderboardService: GetSortedAsync(%s) упал: %s"):format(stat.key, tostring(pagesOrErr)))
		return nil
	end

	local page = pagesOrErr:GetCurrentPage()
	local entries = {}
	for rank, item in ipairs(page) do
		local userId = tonumber(item.key)
		local nameOk, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		entries[rank] = {
			rank = rank,
			name = nameOk and name or ("Player_" .. tostring(userId)),
			valueText = Format.short(EtNum.lbdecode(item.value)),
		}
	end
	return entries
end

local function refreshBoard(stat)
	local entries = fetchTop(stat)
	if not entries then
		return
	end

	local models = findLeaderboardModels(stat.key)
	if #models == 0 then
		warn(("LeaderboardService: не нашёл ни одной World<N>BaseZone.Leaderboards.%s"):format(stat.key))
		return
	end

	for _, model in ipairs(models) do
		local screen = resolveScreen(model)
		if not screen then
			warn(("LeaderboardService: не нашёл BasePart для доски %s"):format(model:GetFullName()))
			continue
		end

		local rows = ensureGui(screen, stat.title)
		clearRows(rows)
		for _, entry in ipairs(entries) do
			local row = createRow(entry.rank, entry.name, entry.valueText, stat.rowColor)
			row.Parent = rows
		end
	end
end

local function refreshAllBoards()
	for _, stat in ipairs(STATS) do
		task.spawn(refreshBoard, stat)
	end
end

function LeaderboardService:KnitStart()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(syncPlayer, player)
	end

	Players.PlayerAdded:Connect(function(player)
		ProfileService:WaitUntilProfileLoaded(player)
		syncPlayer(player)
	end)

	-- Финальная запись — пока профиль ещё у сервера (после PlayerRemoving ProfileService уже отпустил сессию)
	ProfileService.ProfileReleasing:Connect(syncPlayer)

	Players.PlayerRemoving:Connect(function(player)
		-- кэш последней записи больше не нужен (иначе копился бы по записи на каждого побывавшего игрока)
		for _, stat in ipairs(STATS) do
			lastWritten[tostring(player.UserId) .. stat.key] = nil
		end
	end)

	-- Периодическая досинхронизация тех, кто ещё в игре: без этого стат, записанный
	-- при входе, залипает на старом значении до самого выхода игрока.
	task.spawn(function()
		while true do
			task.wait(LeaderboardConfig.SYNC_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(syncPlayer, player)
			end
		end
	end)

	-- Топ-100 на досках всех миров: сразу при старте сервера, затем раз в сутки.
	task.spawn(function()
		refreshAllBoards()
		while true do
			task.wait(LeaderboardConfig.REFRESH_INTERVAL)
			refreshAllBoards()
		end
	end)

	-- Новый мир подгрузился в Workspace во время сессии сервера -> сразу дать ему доски,
	-- не дожидаясь суточного REFRESH_INTERVAL.
	Workspace.ChildAdded:Connect(function(inst)
		if inst.Name:match(WORLD_ZONE_PATTERN) then
			task.wait(1)
			refreshAllBoards()
		end
	end)
end

function LeaderboardService:KnitInit()
	ProfileService = Knit.GetService("ProfileService")
end

return LeaderboardService
