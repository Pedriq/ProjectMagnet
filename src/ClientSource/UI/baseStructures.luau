local Workspace = game:GetService("Workspace")

--[[
	baseStructures — сопоставление «постройка на базе мира -> окно HUD».

	В каждом мире есть зона базы (World1BazeZone, World2BazeZone, ...). Внутри —
	постройки-модели с фиксированными именами, в каждой NPC с тем же именем, а в
	NPC — ProximityPrompt. Имена построек одинаковы во всех мирах, поэтому маппинг
	ведётся по имени постройки и не зависит от количества миров: добавили World5 с
	такой же структурой — промпты заработают без правок кода.

		Постройка   Окно (ключ switch(openPanel) в screens/HUD)
		Buy      -> magnets   (магазин кастеров)
		Upgrade  -> upgrades  (прокачка статов)
		Sell     -> sell      (продажа лута)

	Новая постройка на базе = одна строка в PANEL_BY_BUILDING + ветка в switch у HUD.
]]
local BaseStructures = {}

-- Имя постройки (или NPC внутри неё) -> ключ окна.
BaseStructures.PANEL_BY_BUILDING = {
	Buy = "magnets",
	Upgrade = "upgrades",
	Sell = "sell",
} :: { [string]: string }

--[[
	По сработавшему ProximityPrompt вернуть ключ окна или nil.

	Идём вверх по родителям от промпта до первого предка с известным именем из
	PANEL_BY_BUILDING. Промпт обязан находиться в Workspace — так шаблоны построек,
	лежащие в ReplicatedStorage/ServerStorage, случайно не сматчатся.
]]
function BaseStructures.panelKeyFromPrompt(prompt: Instance): string?
	if not prompt:IsDescendantOf(Workspace) then
		return nil
	end

	local node: Instance? = prompt.Parent
	while node and node ~= Workspace do
		local key = BaseStructures.PANEL_BY_BUILDING[node.Name]
		if key then
			return key
		end
		node = node.Parent
	end

	return nil
end

return BaseStructures
