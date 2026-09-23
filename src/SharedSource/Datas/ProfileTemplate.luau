local ProfileTemplate = {
	Magnet = {
		Name = "BasicMagnet",
		Magnetism = 1,
	},

	OwnedMagnets = {
		Stick = true,
	},

	Stats = {
		Range = 0,
		Agility = 0,
		Capacity = 0,
		Mobility = 0,

		Level = 1,
		Magnetism = "0",
		Rebirth = 0,

		Money = "140",
	},

	-- Добытая руда, которую игрок несёт с собой (см. PlayerOresManager).
	Ores = {
		TotalWeight = 0,
		-- [oreName] = { Weight = number, Pieces = number }
		Items = {},
	},

	Multipliers = {
		Cash = "1",
		Magnetism = "1",
	},
}

return ProfileTemplate
