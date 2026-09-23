local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)

local create = vide.create

-- Clones only the display model; never changes the equipped magnet or its template.
local function MagnetViewport(name: string)
	local camera = create("Camera")({ FieldOfView = 35 })
	local world = create("WorldModel")({ Name = "PreviewWorld" })
	local viewport = create("ViewportFrame")({
		Name = "MagnetViewport",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(210, 210, 210),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -2),
		CurrentCamera = camera,
		camera,
		world,
	})
	local bounds: Vector3? = nil
	local previewModel: Model? = nil
	local initialPivot = CFrame.identity
	local angle = 0
	local function fit()
		if not bounds then
			return
		end
		local size = viewport.AbsoluteSize
		local aspect = if size.Y > 0 then math.max(size.X / size.Y, 0.1) else 0.65
		local distance = math.max(bounds.Y, bounds.X / aspect) * 0.58 / math.tan(math.rad(camera.FieldOfView / 2)) + bounds.Z / 2
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
	end
	local function loadModel()
		if bounds then
			return
		end
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local magnets = assets and assets:FindFirstChild("Magnets")
		local template = magnets and magnets:FindFirstChild(name)
		if not template or not template:IsA("Model") then
			return
		end
		local model = template:Clone()
		for _, item in model:GetDescendants() do
			if item:IsA("BaseScript") or item:IsA("ModuleScript") then
				item:Destroy()
			elseif item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
			elseif item:IsA("ParticleEmitter") or item:IsA("Trail") or item:IsA("Beam") then
				item.Enabled = false
			end
		end
		local box = model:GetBoundingBox()
		model:PivotTo(CFrame.Angles(0, 0, math.rad(-12)) * box:Inverse() * model:GetPivot())
		model.Parent = world
		-- Measure world-aligned bounds after tilting the sword.
		local minimum = Vector3.new(math.huge, math.huge, math.huge)
		local maximum = -minimum
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				for x = -1, 1, 2 do
					for y = -1, 1, 2 do
						for z = -1, 1, 2 do
							local point = part.CFrame * (part.Size * Vector3.new(x, y, z) / 2)
							minimum = minimum:Min(point)
							maximum = maximum:Max(point)
						end
					end
				end
			end
		end
		bounds = maximum - minimum
		model:PivotTo(CFrame.new(-(minimum + maximum) / 2) * model:GetPivot())
		-- Fit the full horizontal rotation envelope so the blade never clips.
		local diameter = math.sqrt(bounds.X * bounds.X + bounds.Z * bounds.Z)
		bounds = Vector3.new(diameter, bounds.Y, diameter)
		initialPivot = model:GetPivot()
		previewModel = model
		fit()
	end
	local resize = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local added = ReplicatedStorage.DescendantAdded:Connect(function(item)
		if item.Name == name or item.Name == "Magnets" or item.Name == "Assets" then
			loadModel()
		end
	end)
	local rotation = RunService.Heartbeat:Connect(function(deltaTime)
		if previewModel then
			angle = (angle + math.rad(35) * deltaTime) % (2 * math.pi)
			previewModel:PivotTo(CFrame.Angles(0, angle, 0) * initialPivot)
		end
	end)
	vide.cleanup(function()
		rotation:Disconnect()
		resize:Disconnect()
		added:Disconnect()
	end)
	loadModel()
	return viewport
end

return MagnetViewport
