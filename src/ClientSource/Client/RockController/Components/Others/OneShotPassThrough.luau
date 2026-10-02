local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local vide = require(ReplicatedStorage.Packages.Vide)
local Data = require(ReplicatedStorage.ClientSource.UI.data)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)

--[[
	OneShotPassThrough — камни, которые игрок ломает с одного удара, не мешают бежать.

	Персонаж симулируется у клиента, поэтому коллизию хитбоксов камней решаем
	локально (CanCollide на клиенте влияет только на этого игрока; хитбоксы и так
	личные — Workspace.PlayersRock.<userId>_Rock). Камень, у которого HP <= урона
	игрока, становится проходимым; сервер ломает его сразу при входе в хитбокс
	магнита, без кулдауна атаки (PlayerMagnetHitboxManager:ApplyOneShots).
	Камни, которым нужно несколько ударов, остаются твёрдыми — как раньше.

	Урон — та же формула, что на сервере: max(1, round(Stats.Magnetism)).
	Клиентская сила отстаёт от серверной на пинг, т.е. урон тут не больше
	серверного — проходимым никогда не станет камень, который сервер не сломает
	одним ударом.

	Полный инвентарь: камень проходим, только если его кусочек ещё влезает
	(сервер не бьёт камни, чья руда не влезает). Заполнил инвентарь — все камни
	снова твёрдые, вперёд по полю не пройти, пока не освободишь место на базе.
	Камень, внутри которого игрок стоит в момент «затвердевания», ждёт, пока он
	выйдет (pendingSolid) — чтобы не застрять/не вылететь.

	Без опроса каждый кадр — всё по событиям:
	  * новый хитбокс камня (DescendantAdded)  -> проверить этот камень;
	  * у камня сменился HP (атрибут "Hp")     -> проверить этот камень;
	  * урон вырос                             -> проверить только ещё твёрдые камни
	                                              (проходимые проходимыми и останутся);
	  * урон упал (ребёрс сбросил силу)        -> проверить все (редко);
	  * изменился набор влезающих руд          -> проверить все (только у границы
	                                              вместимости, не на каждый кусочек).
]]

local OneShotPassThrough = {}

local player = Players.LocalPlayer
local PlayersRockFolder = workspace:WaitForChild("PlayersRock")
local rockFolderName = tostring(player.UserId) .. "_Rock"

-- Камень, который стал твёрдым, пока персонаж стоит внутри него, ждёт, пока
-- игрок выйдет (иначе физика вытолкнет/застрянет). Проверка — таймером, и
-- только пока такие камни есть (редкий случай: инвентарь заполнился посреди камня).
local PENDING_CHECK_INTERVAL = 0.25

---- State
local damage = 1
local solid: { [BasePart]: boolean } = {} -- камни, которые сейчас блокируют игрока
local passable: { [BasePart]: boolean } = {} -- уже проходимые
local pendingSolid: { [BasePart]: boolean } = {} -- должны стать твёрдыми, но игрок внутри
local pendingLoop = false
-- Руды, кусочек которых сейчас влезает в инвентарь переноски: [oreId] = true.
-- Сервер не бьёт камень, чей кусочек не влезает (PlayerMagnetHitboxManager:
-- _HittableTargets), значит такой камень должен блокировать — даже если он «с
-- одного удара». Полный инвентарь = ни одна руда не влезает = все камни твёрдые.
local fittingOres: { [string]: boolean } = {}

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

-- Пересекается ли хитбокс камня с персонажем. Сначала дешёвая проверка
-- расстояния, запрос к физике — только для камней вплотную к игроку.
local function overlapsCharacter(part: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	if (part.Position - root.Position).Magnitude > part.Size.Magnitude / 2 + 4 then
		return false
	end
	overlapParams.FilterDescendantsInstances = { character }
	return #workspace:GetPartsInPart(part, overlapParams) > 0
end

local evaluate: (BasePart) -> ()

local function startPendingLoop()
	if pendingLoop then
		return
	end
	pendingLoop = true
	task.spawn(function()
		while next(pendingSolid) do
			task.wait(PENDING_CHECK_INTERVAL)
			for part in pairs(table.clone(pendingSolid)) do
				pendingSolid[part] = nil
				evaluate(part) -- либо станет твёрдым, либо снова встанет в ожидание
			end
		end
		pendingLoop = false
	end)
end

local function damageFrom(magnetism: any): number
	local ok, value = pcall(function()
		return EtNum.toNumber(EtNum.convert(magnetism))
	end)
	return math.max(1, math.floor((if ok then value else 0) + 0.5))
end

function evaluate(part: BasePart)
	if not part.Parent then
		solid[part], passable[part], pendingSolid[part] = nil, nil, nil
		return
	end
	local hp = part:GetAttribute("Hp")
	if type(hp) ~= "number" then
		return
	end

	-- уже разбит (сервер погасил коллизию на добивании) — всегда проходим
	local oneShot = hp <= damage
	local fits = fittingOres[part:GetAttribute("Section")] == true
	if hp <= 0 or (oneShot and fits) then
		part.CanCollide = false
		solid[part], passable[part], pendingSolid[part] = nil, true, nil
		return
	end

	-- должен блокировать; если игрок прямо сейчас внутри — подождать, пока выйдет
	if not part.CanCollide and overlapsCharacter(part) then
		pendingSolid[part] = true
		startPendingLoop()
		return
	end
	part.CanCollide = true
	solid[part], passable[part], pendingSolid[part] = true, nil, nil
end

-- Какие руды сейчас влезают (как PlayerOreInventory:CanFitPiece на сервере).
local function computeFitting(): { [string]: boolean }
	local free = Data.carryCapacity() - Data.carryCount()
	local result = {}
	for _, oreId in ipairs(OreConfig.Order) do
		local ore = OreConfig.Get(oreId)
		if ore and free >= ore.PieceWeight then
			result[oreId] = true
		end
	end
	return result
end

-- Инвентарь изменился. Пересчитываем камни ТОЛЬКО если сменился набор
-- влезающих руд — это бывает лишь у самой границы вместимости; обычный сбор
-- руды (тысячи событий) сюда почти никогда не доходит.
local function setFitting(newFitting: { [string]: boolean })
	local changed = false
	for _, oreId in ipairs(OreConfig.Order) do
		if (newFitting[oreId] == true) ~= (fittingOres[oreId] == true) then
			changed = true
			break
		end
	end
	fittingOres = newFitting
	if not changed then
		return
	end

	for part in pairs(table.clone(solid)) do
		evaluate(part)
	end
	for part in pairs(table.clone(passable)) do
		evaluate(part)
	end
end

local function track(inst: Instance)
	if not inst:IsA("BasePart") or not inst:GetAttribute("RockIndex") then
		return
	end
	local part = inst :: BasePart
	evaluate(part)
	-- коннекшен умрёт вместе с part (Destroy), отдельная очистка не нужна
	part:GetAttributeChangedSignal("Hp"):Connect(function()
		evaluate(part)
	end)
	part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			solid[part], passable[part], pendingSolid[part] = nil, nil, nil
		end
	end)
end

local function setDamage(newDamage: number)
	if newDamage == damage then
		return
	end
	local grew = newDamage > damage
	damage = newDamage

	if grew then
		-- выросший урон может сделать проходимыми только твёрдые камни
		for part in pairs(table.clone(solid)) do
			evaluate(part)
		end
	else
		for part in pairs(table.clone(passable)) do
			evaluate(part)
		end
	end
end

function OneShotPassThrough.Start()
	-- урон: реактивно от Data.magnetism (обновляется по ProfileService)
	fittingOres = computeFitting()

	vide.root(function()
		vide.effect(function()
			local magnetism = Data.magnetism()
			vide.untrack(function()
				setDamage(damageFrom(magnetism))
			end)
		end)
		-- инвентарь переноски (PlayerManagerService.CarryInventoryChanged -> Data)
		vide.effect(function()
			Data.carryCount()
			Data.carryCapacity()
			vide.untrack(function()
				setFitting(computeFitting())
			end)
		end)
	end)

	local folder = PlayersRockFolder:WaitForChild(rockFolderName)
	folder.DescendantAdded:Connect(track)
	for _, inst in ipairs(folder:GetDescendants()) do
		track(inst)
	end
end

function OneShotPassThrough.Init() end

return OneShotPassThrough
