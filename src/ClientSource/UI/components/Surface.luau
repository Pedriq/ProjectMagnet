local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)
local Format = require(ReplicatedStorage.SharedSource.Utilities.Format)

local create = vide.create
local asset = Format.asset

--[[
	Surface — «сочная» отделка поверхности одним набором слоёв:
	  1. тайловая текстура (та же, что на прогресс-баре);
	  2. белая подсветка у верхнего края;
	  3. лёгкая тень у нижнего края.

	Подсветка и тень — один Frame с UIGradient: цвет белый->чёрный по вертикали,
	а прозрачность высокая в середине, так что видно только светлый верх и тёмный низ.

	Не рисует фон/обводку/скругление самого элемента — только отделку поверх.
	Слои идут с ZIndex = 0, поэтому контент (текст/иконки с ZIndex >= 1) остаётся сверху,
	а сам набор можно спредить в конец списка детей.

	Использование:
	  create("Frame")({
	      BackgroundColor3 = color,
	      create("UICorner")({ CornerRadius = radius }),
	      ...текст, иконки...
	      table.unpack(Surface({ Radius = radius })),
	  })
]]

export type Props = {
	TileSize: UDim2?, -- Optional relative texture size.
	Radius: UDim?, -- скругление слоёв — ставь такое же, как у контейнера (по умолч. 8)
	ZIndex: number?, -- базовый ZIndex слоёв (по умолч. 0 — под контентом)

	Texture: string?, -- id текстуры (по умолч. общая "137638295200351")
	TextureTransparency: number?, -- по умолч. 0.5
	TextureTile: number?, -- размер плитки в пикселях (по умолч. 24)
	TextureColor: Color3?, -- тонировка текстуры (по умолч. без тонировки)

	Highlight: number?, -- сила белой подсветки сверху 0..1 (по умолч. 0.5)
	Shadow: number?, -- сила тени снизу 0..1 (по умолч. 0.28)
}

local function Surface(props: Props)
	props = props or {}
	local radius = props.Radius or UDim.new(0, 8)
	local zi = props.ZIndex or 0

	local texture = props.Texture or "137638295200351"
	local texTransparency = props.TextureTransparency or 0.5
	local tile = props.TextureTile or 24

	local highlight = math.clamp(props.Highlight or 0.5, 0, 1)
	local shadow = math.clamp(props.Shadow or 0.28, 0, 1)

	return {
		-- тайловая текстура
		create("ImageLabel")({
			Name = "SurfaceTexture",
			ZIndex = zi,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = asset(texture),
			ImageColor3 = props.TextureColor,
			ImageTransparency = texTransparency,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = props.TileSize or UDim2.fromOffset(tile, tile),

			create("UICorner")({ CornerRadius = radius }),
		}),

		-- подсветка сверху + тень снизу одним градиентом
		create("Frame")({
			Name = "SurfaceShade",
			ZIndex = zi,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),

			create("UICorner")({ CornerRadius = radius }),
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - highlight), -- верх: белый виден
					NumberSequenceKeypoint.new(0.22, 1),
					NumberSequenceKeypoint.new(0.75, 1),
					NumberSequenceKeypoint.new(1, 1 - shadow), -- низ: чёрный виден
				}),
			}),
		}),
	}
end

return Surface
