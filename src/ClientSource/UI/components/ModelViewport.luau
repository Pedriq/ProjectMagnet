local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local rarityFx = require(ReplicatedStorage.ClientSource.UI.rarityFx)

local create = vide.create
local effect = vide.effect
local cleanup = vide.cleanup
local read = vide.read

local clock = rarityFx.clock

--[[
	ModelViewport — 3D-превью модели (меч/предмет) вместо плоской иконки в
	карточках (WeaponCard/SellItemCard). Клонирует Model в свой WorldModel,
	наводит камеру по боксу модели и медленно крутит её для "живости".

	Model может быть реактивным (function): в SellPanel карточки переиспользуются
	по индексу (vide.indexes), и то, какой предмет сейчас за этой карточкой,
	может со временем смениться — тогда превью должно смениться вместе с ним.
]]

export type Props = {
	Model: Instance? | (() -> Instance?),
	Size: UDim2?,
	AnchorPoint: Vector2?,
	Position: UDim2?,
	ZIndex: number?,
	LayoutOrder: number?,
	Spin: boolean?, -- по умолч. true
	BackgroundTransparency: number?,
	FieldOfView: number?,
	Padding: number?, -- запас вокруг модели, по умолч. 1.35 (меньше = модель крупнее/ближе)
}

local FIELD_OF_VIEW = 30
local PADDING = 1.35
local SPIN_SPEED = 0.5 -- рад/сек
local TILT = 0.32 -- лёгкий наклон камеры сверху, доля от distance

local function ModelViewport(props: Props)
	local worldModel = Instance.new("WorldModel")

	local spin = props.Spin ~= false
	local fieldOfView = props.FieldOfView or FIELD_OF_VIEW
	local padding = props.Padding or PADDING
	local center = Vector3.zero
	local distance = 5

	local function cameraCFrame()
		local angle = if spin then clock() * SPIN_SPEED else 0
		local offset = Vector3.new(math.sin(angle), TILT, math.cos(angle)) * distance
		return CFrame.new(center + offset, center)
	end

	effect(function()
		local model = read(props.Model)
		if not model then
			return
		end

		local clone = model:Clone()
		clone.Parent = worldModel
		cleanup(clone)

		local cframe, size
		if clone:IsA("Model") then
			cframe, size = clone:GetBoundingBox()
		elseif clone:IsA("BasePart") then
			cframe, size = clone.CFrame, clone.Size
		else
			return
		end

		local radius = math.max(size.Magnitude / 2, 0.5)
		distance = radius / math.tan(math.rad(fieldOfView / 2)) * padding
		center = cframe.Position
	end)

	local camera = create("Camera")({
		FieldOfView = fieldOfView,
		FieldOfViewMode = Enum.FieldOfViewMode.Diagonal,
		CFrame = cameraCFrame,
	})

	return create("ViewportFrame")({
		Name = "ModelViewport",
		Size = props.Size or UDim2.fromScale(1, 1),
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = if props.BackgroundTransparency ~= nil then props.BackgroundTransparency else 1,
		CurrentCamera = camera,
		Ambient = Color3.fromRGB(140, 140, 140),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -2, -1),

		worldModel,
		camera,
	})
end

return ModelViewport
