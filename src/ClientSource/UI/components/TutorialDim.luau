local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local create = vide.create
local show = vide.show

--[[
	TutorialDim — затемнение поверх родителя (туториал): гасит элементы интерфейса, которые
	НЕ являются текущей целью, чтобы подсвеченная карточка/кнопка была главной.

	Кладётся ребёнком в карточку (рядом с TutorialPulse), ничего не перехватывает.
	Пока Active() == false — не создаётся вообще.

	  TutorialDim({ Active = () -> boolean, CornerRadius = UDim? })
]]

export type Props = {
	Active: () -> boolean,
	CornerRadius: UDim?,
}

local function TutorialDim(props: Props)
	return show(props.Active, function()
		return create("Frame")({
			Name = "TutorialDim",
			ZIndex = 40, -- выше содержимого карточки, ниже пульса (50)
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,

			create("UICorner")({ CornerRadius = props.CornerRadius or UDim.new(0, 6) }),
		})
	end)
end

return TutorialDim
