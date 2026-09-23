local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local EtNum = require(ReplicatedStorage.Packages.EtNum)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local PlayerWeaponHitboxManager = {}

local WEAPON_HITBOX_FRONT_GAP = 1 -- зазор от игрока до ближней грани хитбокса (студы)

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService
local ClickerService

---- Datas
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)

---- Assets
function PlayerWeaponHitboxManager:CreateWeaponHitbox(player, weaponName)
	print("In create weapon hitbox")
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:FindFirstChild("HumanoidRootPart")

	if not root then
		warn("not root")
		return
	end

	if not WeaponData[weaponName] then
		warn("Weapon data not found for weapon: " .. weaponName)
		return
	end

	if character:FindFirstChild("WeaponHitbox") then
		character:FindFirstChild("WeaponHitbox"):Destroy()
	end

	local size = PlayerManagerService:GetPlayerStatsValues(player).AttackRange

	local hitbox = Instance.new("Part")
	hitbox.Name = "WeaponHitbox"
	hitbox.Size = size
	hitbox.Transparency = 0.9
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

	-- Ближняя грань хитбокса всегда в WEAPON_HITBOX_FRONT_GAP студ перед игроком,
	-- дальше он растёт только вперёд (а не растягиваясь наполовину игроку за спину).
	hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -(WEAPON_HITBOX_FRONT_GAP + size.Z / 2))
	hitbox.Parent = character
end

function PlayerWeaponHitboxManager:CollectTargets(player)
	local OverlapParams = OverlapParams.new()
	OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	OverlapParams.FilterDescendantsInstances = {}

	local hitbox = player.Character and player.Character:FindFirstChild("WeaponHitbox")

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
		if CollectionService:HasTag(part, "RockHitbox") then
			local rockState = PlayerManagerService:GetRockState(
				player.UserId,
				part:GetAttribute("StripId"),
				part:GetAttribute("RockIndex")
			)

			if rockState then
				table.insert(targets, { part = part, rockState = rockState })
			end
		end
	end

	return targets
end

-- Один тик StartPlayerLoop (раз в AttackCooldown) = один удар: начисление, урон
-- и визуальные эффекты (ShakeRock/FlashRock, попап силы) идут разом — не за
-- каждый задетый камень.
function PlayerWeaponHitboxManager:ApplyHit(player)
	local targets = self:CollectTargets(player)
	if #targets == 0 then
		return
	end

	-- Урон по камню = общая накопленная сила игрока (Stats.Strength) ДО начисления за этот взмах.
	local totalStrength = EtNum.convert(ClickerService:GetPlayerStrength(player))
	local damage = math.max(1, math.floor(EtNum.toNumber(totalStrength) + 0.5))

	ClickerService:Click(player)
	-- Ровно 1 раз за взмах — UI-попап прироста силы слушает именно этот сигнал,
	-- а не HitRock (тот стреляет по каждому задетому камню).
	PlayerManagerService.Client.AttackHit:Fire(player)

	-- ВАЖНО: сами part:Destroy() для разбитых камней откладываются ДО ПОСЛЕ всех
	-- HitRock — иначе клиент может получить репликацию удаления part'а раньше самого
	-- события HitRock, DeleteRockVisual снесёт визуал первым, и обработчик
	-- HitRock просто не найдёт камень в VisualizedRocks (эффект удара пропадёт).
	local killedParts = {}

	for _, target in ipairs(targets) do
		local isLethal = self:ApplyDamage(target.rockState, target.part, damage)

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

function PlayerWeaponHitboxManager:ApplyDamage(rockState, part, damage): boolean
	rockState.hp = rockState.hp - damage
	part:SetAttribute("Hp", rockState.hp)

	local isLethal = rockState.hp <= 0
	if isLethal then
		rockState.cut = true
	end

	return isLethal
end

function PlayerWeaponHitboxManager:StartPlayerLoop(player)
	PlayerManagerService.PlayerThreads[player.UserId] = task.spawn(function()
		while player.Parent do
			self:ApplyHit(player)
			task.wait(PlayerManagerService:GetPlayerStatsValues(player).AttackCooldown)
		end
	end)
end

function PlayerWeaponHitboxManager.Start() end

function PlayerWeaponHitboxManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ClickerService = Knit.GetService("ClickerService")
end

return PlayerWeaponHitboxManager
