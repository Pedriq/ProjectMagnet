local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local OreConfig = require(ReplicatedStorage.SharedSource.Datas.OreConfig)
local DamageCurve = require(ReplicatedStorage.SharedSource.Datas.DamageCurve)
local PlayerMagnetHitboxManager = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService
local ClickerService

---- Datas
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
-- Как часто проверять хитбокс на камни «с одного удара» (ApplyOneShots), сек
local ONE_SHOT_SWEEP_INTERVAL = 0.1

---- State
local lastReward = {} -- [player] = os.clock() последнего засчитанного взмаха
local lastBlocked = {} -- [player] = os.clock() последнего уведомления «не влезает» (CarryBlocked)
local BLOCKED_NOTIFY_INTERVAL = 0.75 -- не чаще, чтобы не слать сигнал на каждый тик хитбокса

---- Assets
function PlayerMagnetHitboxManager:CreateMagnetHitbox(player, magnetName)
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:FindFirstChild("HumanoidRootPart")

	if not root then
		warn("not root")
		return
	end

	if not MagnetData[magnetName] then
		warn("Magnet data not found for magnet: " .. magnetName)
		return
	end

	if character:FindFirstChild("MagnetHitbox") then
		character:FindFirstChild("MagnetHitbox"):Destroy()
	end

	local size = PlayerManagerService:GetPlayerStatsValues(player).AttackRange

	local hitbox = Instance.new("Part")
	hitbox.Name = "MagnetHitbox"
	hitbox.Size = size
	-- Невидим: границу хитбокса рисует клиент (HitboxRing — круг на земле).
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanQuery = true
	hitbox.CanTouch = false
	hitbox.Massless = true
	hitbox.Anchored = false
	hitbox.CollisionGroup = "Rock_" .. player.UserId

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = hitbox
	weld.Parent = hitbox

	-- Хитбокс центрирован на игроке — растёт от него во все стороны (а не только
	-- вперёд), так что прокачка ренджи расширяет зону захвата вокруг игрока.
	hitbox.CFrame = root.CFrame
	hitbox.Parent = character
end

-- Хитбокс — квадратная часть, но бьёт по КРУГУ радиуса Size.X / 2 (вписанному
-- в квадрат): ровно то, что игрок видит кольцом на земле (HitboxRing).
-- Камень задет, если ближайшая к центру точка его коробки (по горизонтали) в круге.
local function overlapsCircle(hitbox: BasePart, part: BasePart): boolean
	local radius = hitbox.Size.X / 2
	local p = part.CFrame:PointToObjectSpace(hitbox.Position)
	local halfX, halfZ = part.Size.X / 2, part.Size.Z / 2
	local dx = p.X - math.clamp(p.X, -halfX, halfX)
	local dz = p.Z - math.clamp(p.Z, -halfZ, halfZ)
	return dx * dx + dz * dz <= radius * radius
end

function PlayerMagnetHitboxManager:CollectTargets(player)
	local OverlapParams = OverlapParams.new()
	OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	OverlapParams.FilterDescendantsInstances = {}

	local hitbox = player.Character and player.Character:FindFirstChild("MagnetHitbox")

	if not hitbox then
		return {}
	end

	OverlapParams.CollisionGroup = hitbox.CollisionGroup

	local parts = workspace:GetPartsInPart(hitbox, OverlapParams)

	-- Собираем задетые камни, ничего пока не начисляя и не проигрывая —
	-- иначе на каждый тик хитбокса (их может быть больше, чем реальных взмахов)
	-- будут заново срабатывать урон/начисление/визуальные эффекты.
	local targets = {}
	for _, part in ipairs(parts) do
		if CollectionService:HasTag(part, "RockHitbox") and overlapsCircle(hitbox, part) then
			local rockState = PlayerManagerService:GetRockState(
				player.UserId,
				part:GetAttribute("StripId"),
				part:GetAttribute("RockIndex")
			)

			-- cut — уже разбит этим же тиком/соседним циклом (part ещё не удалён)
			if rockState and not rockState.cut then
				table.insert(targets, { part = part, rockState = rockState })
			end
		end
	end

	return targets
end

-- Урон по камню = общая накопленная сила игрока (Stats.Magnetism) ДО начисления
-- за взмах, пропущенная через DamageCurve (урон растёт медленнее силы). Та же формула — у клиента (OneShotPassThrough): решает, какие камни
-- для него «проходимы».
local function currentDamage(player): number
	local totalMagnetism = EtNum.convert(ClickerService:GetPlayerMagnetism(player))
	return DamageCurve.fromMagnetism(EtNum.toNumber(totalMagnetism))
end

-- Игрок дотянулся до камня, но кусочек не влезает: сообщаем клиенту (BAG FULL + покупка
-- Capacity). Не чаще BLOCKED_NOTIFY_INTERVAL; на сбор руды, когда место есть, не влияет.
function PlayerMagnetHitboxManager:_NotifyBlocked(player, neededWeight: number)
	local now = os.clock()
	if now - (lastBlocked[player] or 0) < BLOCKED_NOTIFY_INTERVAL then
		return
	end
	lastBlocked[player] = now

	local inventory = PlayerManagerService.Components.PlayerOreInventory
	local free = math.max(inventory:GetCapacity(player) - inventory:GetTotalWeight(player), 0)
	PlayerManagerService.Client.CarryBlocked:Fire(player, neededWeight, free)
end

-- Камни в хитбоксе, которые сейчас можно бить. nil — бить нечего/некуда класть.
-- Камни, чей кусочек не влезает в свободное место, не бьём: у руд разный вес кусочка, и при
-- остатке меньше него удар ломал бы камень, а руда пропадала бы. Если бить нечего ТОЛЬКО из-за
-- нехватки места — уведомляем игрока (_NotifyBlocked), даже когда полоска ещё не на 100%.
function PlayerMagnetHitboxManager:_HittableTargets(player)
	local full = PlayerManagerService:IsCarryFull(player)
	local targets = {}
	local blockedNeed: number? = nil
	for _, target in ipairs(self:CollectTargets(player)) do
		local oreId = target.part:GetAttribute("Section")
		if not full and PlayerManagerService:CanCarryOrePiece(player, oreId) then
			table.insert(targets, target)
		else
			local ore = OreConfig.Get(oreId)
			if ore then
				blockedNeed = math.min(blockedNeed or math.huge, ore.PieceWeight)
			end
		end
	end

	if #targets > 0 then
		return targets
	end
	if blockedNeed then
		self:_NotifyBlocked(player, blockedNeed)
	end
	return nil
end

-- Нанести урон списку камней. reward — засчитать взмах (сила за клик + попап
-- AttackHit); не чаще раза в AttackCooldown, см. ApplyHit / ApplyOneShots.
function PlayerMagnetHitboxManager:_HitTargets(player, targets, damage: number, reward: boolean)
	if reward then
		lastReward[player] = os.clock()
		ClickerService:Click(player)
		-- Ровно 1 раз за взмах — UI-попап прироста силы слушает именно этот сигнал,
		-- а не HitRock (тот стреляет по каждому задетому камню).
		PlayerManagerService.Client.AttackHit:Fire(player)
	end

	-- ВАЖНО: сами part:Destroy() для разбитых камней откладываются ДО ПОСЛЕ всех
	-- HitRock — иначе клиент может получить репликацию удаления part'а раньше самого
	-- события HitRock, DeleteRockVisual снесёт визуал первым, и обработчик
	-- HitRock просто не найдёт камень в VisualizedRocks (эффект удара пропадёт).
	local killedParts = {}

	for _, target in ipairs(targets) do
		local isLethal = self:ApplyDamage(player, target.rockState, target.part, damage)

		PlayerManagerService.Client.HitRock:Fire(
			player,
			target.part:GetAttribute("StripId"),
			target.part:GetAttribute("RockIndex"),
			target.part:GetAttribute("MaxHp"),
			target.rockState.hp
		)

		if isLethal then
			table.insert(killedParts, target.part)
		end
	end

	for _, part in ipairs(killedParts) do
		part:SetAttribute("Cut", true)
		part:Destroy()
	end
end

-- Обычный взмах — тик StartPlayerLoop (раз в AttackCooldown): бьёт ВСЕ камни в
-- хитбоксе (в т.ч. те, которым нужно несколько ударов). Начисление, урон и
-- визуальные эффекты — разом, не за каждый задетый камень.
function PlayerMagnetHitboxManager:ApplyHit(player)
	local targets = self:_HittableTargets(player)
	if not targets then
		return
	end

	-- Награда не чаще раза в AttackCooldown НА ВСЕ пути удара: раньше сюда ходил и цикл взмахов, и свип «с одного
	-- удара» (ApplyOneShots) — если свип успевал наградить прямо перед тиком цикла, сила начислялась дважды за
	-- один кулдаун. 0.9 — допуск на дрожание task.wait, чтобы обычный ритм взмахов не терял награду.
	local stats = PlayerManagerService:GetPlayerStatsValues(player)
	local cooldown = stats and stats.AttackCooldown or 0
	local reward = os.clock() - (lastReward[player] or 0) >= cooldown * 0.9
	self:_HitTargets(player, targets, currentDamage(player), reward)
end

-- Камни «с одного удара» ломаются СРАЗУ, как только попали в хитбокс, без
-- ожидания кулдауна атаки (тик StartOneShotSweep, ONE_SHOT_SWEEP_INTERVAL).
-- Камни, которым нужно несколько ударов, здесь не трогаем — их бьёт обычный
-- ApplyHit со своим кулдауном. Награда за взмах (сила + попап) — по-прежнему
-- не чаще раза в AttackCooldown, так что экономика не меняется: быстрее
-- становится только разрушение.
function PlayerMagnetHitboxManager:ApplyOneShots(player)
	local targets = self:_HittableTargets(player)
	if not targets then
		return
	end

	local damage = currentDamage(player)
	local oneShots = {}
	for _, target in ipairs(targets) do
		if target.rockState.hp <= damage then
			table.insert(oneShots, target)
		end
	end
	if #oneShots == 0 then
		return
	end

	local stats = PlayerManagerService:GetPlayerStatsValues(player)
	local cooldown = stats and stats.AttackCooldown or 0
	local reward = os.clock() - (lastReward[player] or 0) >= cooldown
	self:_HitTargets(player, oneShots, damage, reward)
end

function PlayerMagnetHitboxManager:ApplyDamage(player, rockState, part, damage): boolean
	local maxHp = part:GetAttribute("MaxHp")
	local brokenBefore = OreConfig.PiecesBroken(rockState.hp, maxHp)

	rockState.hp = rockState.hp - damage
	part:SetAttribute("Hp", rockState.hp)

	-- Кусочки, отколотые этим ударом, — в инвентарь переноски. Формула та же,
	-- по которой клиент откалывает сегменты модели (OreConfig.PiecesBroken).
	-- Section хитбокса = Id руды (см. RockHitboxManager / OreConfig).
	local newPieces = OreConfig.PiecesBroken(rockState.hp, maxHp) - brokenBefore
	if newPieces > 0 then
		PlayerManagerService:AddOrePieces(player, part:GetAttribute("Section"), newPieces)
	end

	local isLethal = rockState.hp <= 0
	if isLethal then
		rockState.cut = true
		-- коллизия гасится сразу на смертельном ударе (сам part:Destroy() — чуть
		-- позже, после всех HitRock, см. ApplyHit)
		part.CanCollide = false
	end

	return isLethal
end

function PlayerMagnetHitboxManager:StartPlayerLoop(player)
	PlayerManagerService.PlayerThreads[player.UserId] = task.spawn(function()
		while player.Parent do
			local ok, err = pcall(self.ApplyHit, self, player)
			if not ok then
				warn("[PlayerMagnetHitboxManager] swing failed:", err)
			end
			-- статы могли быть уже очищены (игрок выходит) — тогда ждём по умолчанию, а не падаем; нижняя граница
			-- не даёт цикл-«вхолостую», если кулдаун когда-нибудь станет 0
			local stats = PlayerManagerService:GetPlayerStatsValues(player)
			task.wait(math.max(stats and stats.AttackCooldown or 0.5, 0.05))
		end
	end)

	-- Отдельный лёгкий цикл для камней «с одного удара»: один запрос хитбокса
	-- раз в ONE_SHOT_SWEEP_INTERVAL (не каждый кадр). Бегущий игрок проходит
	-- хитбокс камня за ~0.3 сек — проверка раз в 0.1 сек его не пропустит.
	task.spawn(function()
		while player.Parent do
			local ok, err = pcall(self.ApplyOneShots, self, player)
			if not ok then
				warn("[PlayerMagnetHitboxManager] one-shot sweep failed:", err)
			end
			task.wait(ONE_SHOT_SWEEP_INTERVAL)
		end
	end)
end

function PlayerMagnetHitboxManager.Start() end

function PlayerMagnetHitboxManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ClickerService = Knit.GetService("ClickerService")

	Players.PlayerRemoving:Connect(function(player)
		lastReward[player] = nil
		lastBlocked[player] = nil
	end)
end

return PlayerMagnetHitboxManager
