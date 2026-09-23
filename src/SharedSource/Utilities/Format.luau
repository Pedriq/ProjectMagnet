local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EtNum = require(ReplicatedStorage.Packages.EtNum)

local Format = {}

-- Короткое представление большого числа: EtNum-строка / число / EtNum-таблица -> "1.5B", "3.2Qi" ...
-- EtNum.short для маленьких значений отдаёт number, для больших — string, поэтому приводим к строке.
function Format.short(value: any, digits: number?): string
	local ok, result = pcall(EtNum.short, value, digits or 2)
	if ok and result ~= nil then
		return tostring(result)
	end
	return tostring(value)
end

-- Нормализует id картинки в Content-URI: "rbxassetid://123", "123" (голый id) или "" -> корректный uri
function Format.asset(id: string?): string
	if not id or id == "" then
		return ""
	end
	if string.match(id, "^%s*%d+%s*$") then
		return "rbxassetid://" .. string.match(id, "%d+")
	end
	return id
end

return Format
