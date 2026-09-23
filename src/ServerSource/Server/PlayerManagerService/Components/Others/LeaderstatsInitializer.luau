local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)
local LeaderstatsInitializer = {}

---- Utilities

---- Knit Services
local PlayerManagerService
local ProfileService

---- Datas

---- Assets
-- лидерстаты: Folder "leaderstats" с двумя StringValue (Magnetism/Money) — их видит
-- стандартная таблица игроков Roblox. Значения = Format.short (то же короткое
-- представление, что в HUD), т.к. Stats.Magnetism/Money — EtNum-строки произвольной точности.
function LeaderstatsInitializer:InitLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local magnetism = Instance.new("StringValue")
	magnetism.Name = "Magnetism"
	magnetism.Value = Format.short(ProfileService:GetData(player, { "Stats", "Magnetism" }) or "0")
	magnetism.Parent = leaderstats

	local money = Instance.new("StringValue")
	money.Name = "Money"
	money.Value = Format.short(ProfileService:GetData(player, { "Stats", "Money" }) or "0")
	money.Parent = leaderstats

	leaderstats.Parent = player

	-- ProfileService.UpdateSpecificData — общий сигнал на ВСЕХ игроков, поэтому
	-- фильтруем по player; отключается в DataCleaner:CleanLeaderstats.
	PlayerManagerService.LeaderstatsConnections[player.UserId] =
		ProfileService.UpdateSpecificData:Connect(function(changedPlayer, redirectories, newValue)
			if changedPlayer ~= player or redirectories[1] ~= "Stats" then
				return
			end

			if redirectories[2] == "Magnetism" then
				magnetism.Value = Format.short(newValue)
			elseif redirectories[2] == "Money" then
				money.Value = Format.short(newValue)
			end
		end)
end

function LeaderstatsInitializer.Start() end

function LeaderstatsInitializer.Init()
	PlayerManagerService = Knit.GetService("PlayerManagerService")
	ProfileService = Knit.GetService("ProfileService")
end

return LeaderstatsInitializer
