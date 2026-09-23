--[[
	VoxelMagnetBuilder — собирает воксельную модель оружия в стиле Trove
	из плоского «чертежа» (вид сбоку).

	Соседние воксели одного символа сливаются в один Part (greedy-меш) —
	получаются десятки частей вместо сотен.

	Результат: Model
	  • невидимый Handle (PrimaryPart) в центре хвата
	  • все части сварены к Handle (WeldConstraint), не заякорены
	  • тег "Magnet"
	Кладётся в ReplicatedStorage.Assets.Magnets и работает с текущим MagnetHandler.

	Система координат чертежа:
	  строка 1 (верхняя) -> максимальный Y, символ 1 (левый) -> минимальный X.
	  Клинок «растёт» вверх (+Y). Толщина набирается по Z, симметрично от 0.
]]

local CollectionService = game:GetService("CollectionService")

export type PaletteEntry = {
	Color: Color3,
	Material: Enum.Material?, -- по умолч. SmoothPlastic
	Reflectance: number?,
	Transparency: number?,
	Depth: number?, -- толщина по Z в вокселях (по умолч. Blueprint.Depth)
	Name: string?, -- имя Part'ов из этого символа (по умолч. сам символ)
	Light: boolean?, -- вставить PointLight цвета вокселя (для «светящихся»)
}

export type Blueprint = {
	Name: string,
	Voxel: number?, -- размер вокселя в studs (по умолч. 0.16)
	Depth: number?, -- базовая толщина по Z в вокселях (по умолч. 2)
	Palette: { [string]: PaletteEntry },
	Grid: { string }, -- строки сверху вниз, символы слева направо
	Grip: { string }, -- символы рукояти: по их общему габариту строится Handle
	HandleCFrame: CFrame?, -- поворот/сдвиг всей модели относительно Handle (центр кисти)
}

-- символы, которые считаются пустотой
local EMPTY = { [" "] = true, ["."] = true, ["_"] = true }

local VoxelMagnetBuilder = {}

local function key(x: number, y: number, z: number): string
	return x .. "," .. y .. "," .. z
end

-- чертёж -> map вокселей { [key] = symbol } + отсортированный список координат
local function rasterize(bp: Blueprint)
	local baseDepth = bp.Depth or 2
	local voxels: { [string]: string } = {}
	local coords: { { number } } = {}

	local height = #bp.Grid
	for r = 1, height do
		local row = bp.Grid[r]
		local vy = height - r -- верхняя строка -> максимальный Y
		for c = 1, #row do
			local sym = string.sub(row, c, c)
			if not EMPTY[sym] then
				local entry = bp.Palette[sym]
				assert(entry, `VoxelMagnet "{bp.Name}": в палитре нет символа "{sym}"`)

				local depth = entry.Depth or baseDepth
				local z0 = -math.floor(depth / 2)
				local vx = c - 1

				for zi = 0, depth - 1 do
					local vz = z0 + zi
					voxels[key(vx, vy, vz)] = sym
					table.insert(coords, { vx, vy, vz })
				end
			end
		end
	end

	table.sort(coords, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		if a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[3] < b[3]
	end)

	return voxels, coords
end

-- greedy-слияние вокселей одного символа в прямоугольные боксы
local function greedyBoxes(voxels: { [string]: string }, coords: { { number } })
	local visited: { [string]: boolean } = {}
	local boxes = {}

	local function fits(x: number, y: number, z: number, sym: string): boolean
		local k = key(x, y, z)
		return voxels[k] == sym and not visited[k]
	end

	for _, c in ipairs(coords) do
		local x, y, z = c[1], c[2], c[3]
		if not visited[key(x, y, z)] then
			local sym = voxels[key(x, y, z)]

			-- растём по X
			local w = 1
			while fits(x + w, y, z, sym) do
				w += 1
			end

			-- растём по Y (вся строка шириной w должна быть свободна)
			local h = 1
			while (function()
				for i = 0, w - 1 do
					if not fits(x + i, y + h, z, sym) then
						return false
					end
				end
				return true
			end)() do
				h += 1
			end

			-- растём по Z (весь слой w*h должен быть свободен)
			local d = 1
			while (function()
				for i = 0, w - 1 do
					for j = 0, h - 1 do
						if not fits(x + i, y + j, z + d, sym) then
							return false
						end
					end
				end
				return true
			end)() do
				d += 1
			end

			for i = 0, w - 1 do
				for j = 0, h - 1 do
					for l = 0, d - 1 do
						visited[key(x + i, y + j, z + l)] = true
					end
				end
			end

			table.insert(boxes, {
				sym = sym,
				min = Vector3.new(x, y, z),
				size = Vector3.new(w, h, d),
			})
		end
	end

	return boxes
end

-- центр рукояти (в вокселях) и её габарит -> для невидимого Handle
local function gripBounds(bp: Blueprint, voxels: { [string]: string })
	local gripSet: { [string]: boolean } = {}
	for _, s in ipairs(bp.Grip) do
		gripSet[s] = true
	end

	local min: Vector3?, max: Vector3? = nil, nil
	for k, sym in pairs(voxels) do
		if gripSet[sym] then
			local sx, sy, sz = string.match(k, "(-?%d+),(-?%d+),(-?%d+)")
			local v = Vector3.new(tonumber(sx), tonumber(sy), tonumber(sz))
			min = if min then min:Min(v) else v
			max = if max then max:Max(v) else v
		end
	end

	assert(min and max, `VoxelMagnet "{bp.Name}": ни один воксель не помечен как Grip`)
	max += Vector3.one -- воксель i занимает [i, i + 1)
	return (min + max) / 2, max - min
end

function VoxelMagnetBuilder.Build(bp: Blueprint): Model
	local voxel = bp.Voxel or 0.16
	local handleCF = bp.HandleCFrame or CFrame.identity

	local voxels, coords = rasterize(bp)
	local boxes = greedyBoxes(voxels, coords)
	local gripCenter, gripSize = gripBounds(bp, voxels)

	local model = Instance.new("Model")
	model.Name = bp.Name

	-- невидимый Handle в центре хвата: к нему всё сваривается и его берёт MagnetHandler
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = gripSize * voxel
	handle.Transparency = 1
	handle.Massless = true
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.CastShadow = false
	handle.CFrame = handleCF
	handle.Parent = model
	model.PrimaryPart = handle

	local counters: { [string]: number } = {}
	for _, box in ipairs(boxes) do
		local entry = bp.Palette[box.sym]
		local center = box.min + box.size / 2

		local part = Instance.new("Part")
		local baseName = entry.Name or box.sym
		counters[baseName] = (counters[baseName] or 0) + 1
		part.Name = baseName .. counters[baseName]
		part.Size = box.size * voxel
		part.CFrame = handleCF * CFrame.new((center - gripCenter) * voxel)
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = true
		part.Color = entry.Color
		part.Material = entry.Material or Enum.Material.SmoothPlastic
		part.Reflectance = entry.Reflectance or 0
		part.Transparency = entry.Transparency or 0
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		if entry.Light then
			local light = Instance.new("PointLight")
			light.Color = entry.Color
			light.Brightness = 2
			light.Range = 8
			light.Parent = part
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part

		part.Parent = model
	end

	CollectionService:AddTag(model, "Magnet")
	return model
end

return VoxelMagnetBuilder
