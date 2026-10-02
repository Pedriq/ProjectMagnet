return {
	AttacksCooldawn = 0.5, -- базовая скорость атаки (Agility 1): 2 удара в секунду
	AgilitySpeedPerLevel = 0.1, -- +10% скорости атаки за уровень Agility (как написано в панели Upgrades)
	MinAttackCooldown = 0.15, -- потолок скорости: не чаще ~6.7 ударов в секунду
	WalkSpeed = 16,
	InvetoryCapacity = 300, -- стартовая вместимость инвентаря переноски (уровень Capacity 1), в единицах веса руды
	CapacityPerLevel = 100, -- прибавка вместимости за каждый уровень прокачки Capacity
	AttackRange = Vector3.new(8, 0.2, 8) / 1.5, -- X = Z: хитбокс квадратный в плане (см. RangeScale); /1.5 — уменьшенный размер
}
