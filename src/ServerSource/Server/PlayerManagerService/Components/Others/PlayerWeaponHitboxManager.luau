local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local BaseStatsValues = require(ReplicatedStorage.SharedSource.Datas.BaseStatsValues)
local PlayerWeaponHitboxManager = {}

---- How often we check hitbox overlap. The attack cooldown is checked inside the loop.
local HITBOX_CHECK_INTERVAL = 0.1

-- ТЕСТ: фиксированный урон по камням вместо Progress.Fat. nil — брать из профиля.
local TEST_DAMAGE = 10
-- ТЕСТ: огромный полупрозрачный хитбокс атаки (для теста производительности). nil — обычный.
local TEST_HITBOX_SIZE = Vector3.new(60, 10, 60)
local TEST_HITBOX_TRANSPARENCY = 0.85

---- [userId] = os.clock() timestamp of the last landed attack
local lastAttackTime = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService
local RockService

---- Datas

---- Assets
function PlayerWeaponHitboxManager:CreateWeaponHitbox(player)
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:FindFirstChild("HumanoidRootPart")

	if not root then
		warn("not root")
		return
	end

	if character:FindFirstChild("WeaponHitbox") then
		character:FindFirstChild("WeaponHitbox"):Destroy()
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = "WeaponHitbox"
	hitbox.Size = TEST_HITBOX_SIZE or PlayerManagerService:GetPlayerStatsValues(player).AttackRange
	hitbox.Transparency = TEST_HITBOX_TRANSPARENCY or 1
	hitbox.Color = Color3.fromRGB(255, 60, 60)
	hitbox.CastShadow = false
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

	-- В тестовом режиме хитбокс по центру игрока (бьёт во все стороны), иначе — чуть впереди.
	hitbox.CFrame = root.CFrame * (TEST_HITBOX_SIZE and CFrame.identity or CFrame.new(0, 0, -3))
	hitbox.Parent = character
end

function PlayerWeaponHitboxManager:CheckHitsForPlayer(player)
	local OverlapParams = OverlapParams.new()
	OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	OverlapParams.FilterDescendantsInstances = {}

	local hitbox = player.Character and player.Character:FindFirstChild("WeaponHitbox")

	if not hitbox then
		return {}
	end

	-- Кулдаун атаки по камням фиксированный (BaseStatsValues.RockAttackCooldown) —
	-- не зависит ни от кликов, ни от Agility-стата (PlayerStatsContainer).
	local attackCooldown = BaseStatsValues.RockAttackCooldown
	local now = os.clock()

	if lastAttackTime[player.UserId] and now - lastAttackTime[player.UserId] < attackCooldown then
		return {}
	end

	OverlapParams.CollisionGroup = hitbox.CollisionGroup

	local parts = workspace:GetPartsInPart(hitbox, OverlapParams)

	local hit = false
	-- 2026-09-15: урон переведён с Level на Fat по просьбе владельца (было PlayerManagerService:GetPlayerLevel).
	-- ВНИМАНИЕ: Fat в профиле ничем не ограничен и продолжает расти даже после того, как Level упёрся в потолок
	-- реберса (Rebirth × 10) — то есть игрок, который закапался на потолке и продолжает фармить, будет наращивать
	-- урон по камням бесконечно, хотя по уровню его прогресс стоит на месте. Обсуждали это отдельно — решение
	-- оставить как есть (без клампа потолком реберса).
	local damage = TEST_DAMAGE or PlayerManagerService:GetPlayerFat(player) or 1

	-- Хитбоксы всех игроков стоят в одних координатах, а overlap по коллижн-группе
	-- возвращает и чужие (Rock_X ↔ Rock_Y/Default коллидят по умолчанию). Бьём
	-- только свои — иначе ApplyDamage добьёт чужой парт, а свой оставит с cut=true.
	local ownFolderName = player.UserId .. "_Rock"

	for _, part in ipairs(parts) do
		if CollectionService:HasTag(part, "RockHitbox") then
			local stripFolder = part.Parent

			if not stripFolder or not stripFolder.Parent or stripFolder.Parent.Name ~= ownFolderName then
				continue
			end

			local rockState = PlayerManagerService:GetRockState(
				player.UserId,
				part:GetAttribute("StripId"),
				part:GetAttribute("RockIndex")
			)

			if not rockState then
				continue
			end

			if not hit then
				hit = true
				lastAttackTime[player.UserId] = now
				-- PlayerManagerService:PlayAttackAnimation(player)
			end

			self:ApplyDamage(player, rockState, part, damage)
		end
	end

	return {}
end

function PlayerWeaponHitboxManager:ApplyDamage(player, rockState, part, damage)
	-- Камень уже добит, но модель ещё не удалилась (отложенный Destroy) — не бьём повторно.
	if rockState.cut then
		return
	end

	rockState.hp = rockState.hp - damage
	part:SetAttribute("Hp", rockState.hp)
	PlayerManagerService.Client.HitRock:Fire(
		player,
		part:GetAttribute("StripId"),
		part:GetAttribute("RockIndex"),
		part:GetAttribute("MaxHp"),
		rockState.hp
	)

	if rockState.hp <= 0 then
		rockState.cut = true
		if part then
			part:SetAttribute("Cut", true)
			-- Уничтожаем на следующий кадр: атрибут Cut успевает реплицироваться
			-- раньше удаления, и клиент в DescendantRemoving видит его выставленным
			-- (иначе при ваншоте импакт-развал не проигрывается).
			task.defer(function()
				if part.Parent then
					part:Destroy()
				end
			end)
		end
	end
end

function PlayerWeaponHitboxManager:StartPlayerLoop(player)
	lastAttackTime[player.UserId] = nil

	PlayerManagerService.PlayerThreads[player.UserId] = task.spawn(function()
		while player.Parent do
			-- pcall: разовая ошибка в проверке хитов не должна убивать поток
			-- навсегда — иначе игрок до конца сессии не может ломать камни.
			local ok, err = pcall(self.CheckHitsForPlayer, self, player)

			if not ok then
				warn(
					("[PlayerWeaponHitboxManager] CheckHitsForPlayer failed for %s: %s"):format(
						player.Name,
						tostring(err)
					)
				)
			end

			task.wait(HITBOX_CHECK_INTERVAL)
		end
	end)
end

function PlayerWeaponHitboxManager.Start() end

function PlayerWeaponHitboxManager.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	RockService = Knit.GetService("RockService")
end

return PlayerWeaponHitboxManager
