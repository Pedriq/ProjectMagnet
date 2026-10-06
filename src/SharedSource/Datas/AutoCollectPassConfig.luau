--[[
	AutoCollectPassConfig — Game Pass «OP Auto Collect» (кнопка в колонке донат-кнопок HUD).

	Владелец пасса автоматически получает деньги от пресса (profile.Press.Unclaimed), не
	вставая на HydraulicPress.Collect — см. PressCollectHandler. Владение хранится в профиле
	(profile.AutoCollectPass) и дополнительно подтверждается UserOwnsGamePassAsync при входе
	(AutoCollectPassHandler), поэтому переживает перезаход, а кнопка в HUD остаётся скрытой.
]]
return {
	GamePassId = 2006751727,
}
