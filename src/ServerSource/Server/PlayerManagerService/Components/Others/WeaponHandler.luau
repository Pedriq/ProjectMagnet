local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RangeScale = require(ReplicatedStorage.SharedSource.Utilities.RangeScale)
local WeaponData = require(ReplicatedStorage.SharedSource.Datas.WeaponData)
local WeaponHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas
local weponFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Weapons")

---- Assets
function WeaponHandler:GiveWeapon(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()

	for _, child in ipairs(character:GetChildren()) do
		if child:HasTag("Weapon") then
			child:Destroy()
		end
	end

	local playerWeapon = PlayerManagerService:GetPlayerWeapon(player)

	if not playerWeapon then
		return
	end

	-- Модели в этой папке названы отображаемым именем меча ("Chef's Favourite"),
	-- а не внутренним ключом WeaponData ("ChefsFavourite") — несмотря на то, что
	-- комментарий в WeaponData.luau утверждает обратное. Поэтому ищем по .Name
	-- конфига в первую очередь, а ключ/сырое значение — как подстраховка на
	-- случай другого нейминга ассетов.
	local weaponKey = WeaponData.resolveKey(playerWeapon.Name)
	local weaponCfg = weaponKey and WeaponData[weaponKey]
	local weaponTemplate = (weaponCfg and weponFolder:FindFirstChild(weaponCfg.Name))
		or (weaponKey and weponFolder:FindFirstChild(weaponKey))
		or weponFolder:FindFirstChild(playerWeapon.Name)

	if not weaponTemplate then
		return
	end

	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not rightHand then
		return
	end

	local weaponClone = weaponTemplate:Clone()
	local weaponHandle = weaponClone:FindFirstChild("Handle")

	if not weaponHandle then
		warn("No 'Handle'!")
		return
	end

	CollectionService:AddTag(weaponClone, "Weapon")
	weaponClone.Parent = character

	-- Масштаб (по Range) — ДО выравнивания по руке, иначе WeldConstraint зафиксирует
	-- оружие в позиции, посчитанной для старого размера.
	--
	-- Читаем уровень напрямую из профиля, а не из атрибута "RangeLevel" — тот
	-- выставляет отдельный скрипт (PlayerStatsInitializer) асинхронно через
	-- task.spawn, и при заходе на сервер персонаж иногда успевает заспавниться
	-- раньше, чем атрибут вообще появится (тогда брался дефолт 1 — маленький меч).
	local rangeLevel = PlayerManagerService:GetPlayerRange(player) or 1
	weaponClone:ScaleTo(RangeScale.Multiplier(rangeLevel))

	local weld = Instance.new("WeldConstraint")
	weld.Name = "WeaponWeld"

	local gripAttachment = weaponHandle:FindFirstChild("GripAttachment")
		or weaponClone:FindFirstChild("GripAttachment", true)
	local handAttachment = rightHand:FindFirstChild("RightGripAttachment")

	if gripAttachment and handAttachment then
		-- gripAttachment may not be parented to weaponHandle, so work in world space:
		-- desired weaponHandle offset = handAttachment.WorldCFrame * (gripAttachment.WorldCFrame relative to weaponHandle):Inverse()
		local gripOffsetFromHandle = weaponHandle.CFrame:ToObjectSpace(gripAttachment.WorldCFrame)
		weaponHandle.CFrame = handAttachment.WorldCFrame * gripOffsetFromHandle:Inverse()
	else
		if not gripAttachment then
			warn("GripAttachment not found anywhere under weapon model:", weaponClone:GetFullName())
		end
		if not handAttachment then
			warn("RightGripAttachment not found under RightHand:", rightHand:GetFullName())
		end
		weaponHandle.CFrame = rightHand.CFrame
	end

	weld.Part0 = rightHand
	weld.Part1 = weaponHandle
	weld.Parent = weaponHandle
end

function WeaponHandler.Start() end

function WeaponHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return WeaponHandler
