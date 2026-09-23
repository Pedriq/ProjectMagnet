local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local vide = require(ReplicatedStorage.Packages.Vide)

local source = vide.source
local cleanup = vide.cleanup

--[[
	viewportScale — глобальный коэффициент масштаба интерфейса.

	Весь UI нарисован пиксельными offset'ами (Size, UICorner, UIStroke,
	UIPadding, TextSize, мелкие блики) и «родной» на опорном разрешении ниже.
	Вместо переписывания сотен размеров в доли — один UIScale на экран,
	Scale которого равен этому источнику. См. screens/HUD (обёртка "Content").

	viewportScale() -> () -> number
	  Vide-источник: math.min(vpX/refX, vpY/refY), зажатый в [MIN, MAX].
	  Обновляется при ресайзе окна и при пересоздании камеры.
	  Вызывать внутри реактивной области Vide (внутри компонента).
]]

-- Разрешение, при котором интерфейс показывается в «родных» пикселях (scale = 1).
-- Меньше REFERENCE -> крупнее UI на всех экранах; больше -> мельче.
-- 1280x720 ≈ типовое окно Studio / небольшой ноутбук: на таком UI как раньше,
-- а на 1080p и выше — крупнее.
local REFERENCE = Vector2.new(1280, 720)
-- На ultrawide / 4K не раздувать сверх меры, на маленьком экране не схлопывать.
local MIN_SCALE = 0.7
local MAX_SCALE = 1.6

local function viewportScale(): () -> number
	local scale = source(1)

	local function recompute()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		if vp.X <= 0 or vp.Y <= 0 then
			return
		end
		local s = math.min(vp.X / REFERENCE.X, vp.Y / REFERENCE.Y)
		scale(math.clamp(s, MIN_SCALE, MAX_SCALE))
	end

	-- ViewportSize живёт на камере, а камера может пересоздаться (спавн, смена
	-- CurrentCamera) — переподключаемся к новой и сразу пересчитываем.
	local vpConn: RBXScriptConnection? = nil
	local function bindCamera()
		if vpConn then
			vpConn:Disconnect()
			vpConn = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			vpConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(recompute)
		end
		recompute()
	end

	bindCamera()
	local camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

	cleanup(function()
		camConn:Disconnect()
		if vpConn then
			vpConn:Disconnect()
		end
	end)

	return scale
end

return viewportScale
