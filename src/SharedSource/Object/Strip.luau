local Strip = {}
Strip.__index = Strip

function Strip.new(stripId, xPos, zPos, section, rockCount, rockMaxHp)
	local self = setmetatable({
		stripId = stripId,
		xPos = xPos,
		zPos = zPos,
		section = section,
		rockCount = rockCount,
		rockMaxHp = rockMaxHp,
	}, Strip)
	return self
end

return Strip
