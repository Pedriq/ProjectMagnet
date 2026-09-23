local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RangeScale = require(ReplicatedStorage.SharedSource.Utilities.RangeScale)
local MagnetData = require(ReplicatedStorage.SharedSource.Datas.MagnetData)
local MagnetHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas
local weponFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Magnets")

---- Assets
function MagnetHandler:GiveMagnet(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()

	for _, child in ipairs(character:GetChildren()) do
		if child:HasTag("Magnet") then
			child:Destroy()
		end
	end

	local playerMagnet = PlayerManagerService:GetPlayerMagnet(player)

	if not playerMagnet then
		return
	end

	-- Модели в этой папке названы отображаемым именем меча ("Chef's Favourite"),
	-- а не внутренним ключом MagnetData ("ChefsFavourite") — несмотря на то, что
	-- комментарий в MagnetData.luau утверждает обратное. Поэтому ищем по .Name
	-- конфига в первую очередь, а ключ/сырое значение — как подстраховка на
	-- случай другого нейминга ассетов.
	local magnetKey = MagnetData.resolveKey(playerMagnet.Name)
	local magnetCfg = magnetKey and MagnetData[magnetKey]
	local magnetTemplate = (magnetCfg and weponFolder:FindFirstChild(magnetCfg.Name))
		or (magnetKey and weponFolder:FindFirstChild(magnetKey))
		or weponFolder:FindFirstChild(playerMagnet.Name)

	if not magnetTemplate then
		return
	end

	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not rightHand then
		return
	end

	local magnetClone = magnetTemplate:Clone()
	local magnetHandle = magnetClone:FindFirstChild("Handle")

	if not magnetHandle then
		warn("No 'Handle'!")
		return
	end

	CollectionService:AddTag(magnetClone, "Magnet")
	magnetClone.Parent = character

	-- Масштаб (по Range) — ДО выравнивания по руке, иначе WeldConstraint зафиксирует
	-- оружие в позиции, посчитанной для старого размера.
	--
	-- Читаем уровень напрямую из профиля, а не из атрибута "RangeLevel" — тот
	-- выставляет отдельный скрипт (PlayerStatsInitializer) асинхронно через
	-- task.spawn, и при заходе на сервер персонаж иногда успевает заспавниться
	-- раньше, чем атрибут вообще появится (тогда брался дефолт 1 — маленький меч).
	local rangeLevel = PlayerManagerService:GetPlayerRange(player) or 1
	magnetClone:ScaleTo(RangeScale.Multiplier(rangeLevel))

	local weld = Instance.new("WeldConstraint")
	weld.Name = "MagnetWeld"

	local gripAttachment = magnetHandle:FindFirstChild("GripAttachment")
		or magnetClone:FindFirstChild("GripAttachment", true)
	local handAttachment = rightHand:FindFirstChild("RightGripAttachment")

	if gripAttachment and handAttachment then
		-- gripAttachment may not be parented to magnetHandle, so work in world space:
		-- desired magnetHandle offset = handAttachment.WorldCFrame * (gripAttachment.WorldCFrame relative to magnetHandle):Inverse()
		local gripOffsetFromHandle = magnetHandle.CFrame:ToObjectSpace(gripAttachment.WorldCFrame)
		magnetHandle.CFrame = handAttachment.WorldCFrame * gripOffsetFromHandle:Inverse()
	else
		if not gripAttachment then
			warn("GripAttachment not found anywhere under magnet model:", magnetClone:GetFullName())
		end
		if not handAttachment then
			warn("RightGripAttachment not found under RightHand:", rightHand:GetFullName())
		end
		magnetHandle.CFrame = rightHand.CFrame
	end

	weld.Part0 = rightHand
	weld.Part1 = magnetHandle
	weld.Parent = magnetHandle
end

function MagnetHandler.Start() end

function MagnetHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return MagnetHandler
