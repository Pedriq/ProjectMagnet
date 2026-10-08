local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local RebirthConfig = require(ReplicatedStorage.SharedSource.Datas.RebirthConfig)
local MarketplaceReceiptRouter = require(ReplicatedStorage.SharedSource.Utilities.MarketplaceReceiptRouter)
local RebirthHandler = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Knit Services
local PlayerManagerService

---- Datas

---- Assets
function RebirthHandler:CanRebirth(player)
	local currentLevel = PlayerManagerService:GetPlayerLevel(player)
	local rebirths = PlayerManagerService:GetPlayerRebirths(player)
	local requiredLevel = RebirthConfig.RequiredLevelForRebirth(rebirths)
	return tonumber(currentLevel) >= requiredLevel
end

-- Сам ребёрс без проверки уровня: общий для обычного (Rebirth) и платного (Skip).
function RebirthHandler:ApplyRebirth(player)
	local playerRebirths = PlayerManagerService:GetPlayerRebirths(player)

	playerRebirths += 1

	PlayerManagerService:ChangePlayerLevel(player, 1)
	PlayerManagerService:ChangePlayerMagnetism(player, 0)
	PlayerManagerService:ChangePlayerRebirths(player, playerRebirths)
	PlayerManagerService:ChangePlayerCashMultiplier(player, 1 + playerRebirths * RebirthConfig.CashMultiplierPerRebirth)
	PlayerManagerService:ChangePlayerMagnetismMultiplier(
		player,
		1 + playerRebirths * RebirthConfig.MagnetismMultiplierPerRebirth
	)
end

function RebirthHandler:Rebirth(player)
	if not self:CanRebirth(player) then
		return
	end

	self:ApplyRebirth(player)
end

-- Skip Rebirth: промпт дев-продукта ступени, соответствующей числу реберсов игрока.
function RebirthHandler:PromptSkip(player)
	local step = RebirthConfig.SkipStepFor(PlayerManagerService:GetPlayerRebirths(player) or 0)
	if step.ProductId == 0 then
		warn("[Rebirth] ProductId для Skip Rebirth не задан в RebirthConfig")
		return
	end

	MarketplaceService:PromptProductPurchase(player, step.ProductId)
end

function RebirthHandler.Start()
	-- Повторная доставка чека второй ребёрс не выдаёт — идемпотентность в MarketplaceReceiptRouter.
	-- Каждая ступень — свой дев-продукт, все дают один ребёрс без проверки уровня.
	for _, step in ipairs(RebirthConfig.SkipSteps) do
		if step.ProductId ~= 0 then
			MarketplaceReceiptRouter.Register(step.ProductId, function(player)
				RebirthHandler:ApplyRebirth(player)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end)
		end
	end
end

function RebirthHandler.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
end

return RebirthHandler
