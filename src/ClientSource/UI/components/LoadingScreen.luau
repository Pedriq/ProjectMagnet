local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local vide = require(ReplicatedStorage.Packages.Vide)
local viewportScale = require(ReplicatedStorage.ClientSource.UI.viewportScale)

local create = vide.create
local source = vide.source
local cleanup = vide.cleanup

--[[
	LoadingScreen — заглушка загрузки на LOADING_TIME секунд в «пластиковом» стиле LEGO.

	  * фон: глянцевый градиент, плавно перетекающий между цветами игры (синий -> бирюзовый -> фиолетовый), поверх —
	    слабые «шипы» (studs) как на базовой пластине LEGO и мягкий диагональный блик;
	  * по центру покачивающийся заголовок: «выдавленные» слои текста дают объём цельной пластиковой надписи;
	  * под ним полоса прогресса (0 -> 100 % за всё время, плавное ускорение/замедление) и проценты;
	  * дождь из магнитов: подковы из скруглённых кирпичиков, у каждой свой размер, скорость, вращение и покачивание.

	Всё рисуется из Frame/UICorner/UIGradient — картинок и ассетов нет.

	ВРЕМЯ. Вся анимация идёт от одного источника timeline — секунд РЕАЛЬНО ОТРИСОВАННОГО времени: его двигает RenderStepped,
	а шаг одного кадра ограничен MAX_FRAME_STEP. Поэтому подвисание клиента во время старта Knit (тяжёлая синхронная работа
	до первого кадра) не «съедает» 3.5 с: отсчёт начинается с первого показанного кадра, а долгий кадр не перематывает
	полосу. Страховочный таймер по реальному времени всё равно снимает экран, если RenderStepped не идёт.

	КОНЕЦ. Через Duration секунд перехват ввода выключается (Active у фона = false), затем FADE_TIME секунд растворение
	(CanvasGroup.GroupTransparency), после чего ScreenGui УНИЧТОЖАЕТСЯ и вызывается OnFinished. Важно: destroy у vide.mount
	останавливает только эффекты и НЕ удаляет Instance'ы — поэтому экран удаляет себя сам. Иначе невидимый Active-фон
	остался бы в PlayerGui и глотал клики (gameProcessed = true -> ClickerController игнорирует нажатия).

	  LoadingScreen({ Duration = 3.5?, OnFinished = (() -> ())? }) -> ScreenGui
]]

local TITLE = "+1 Magnetism to Mining"
local LOADING_TIME = 3.5
local FADE_TIME = 0.3 -- растворение уже ПОСЛЕ Duration; ввод к этому моменту не блокируется
local MAX_FRAME_STEP = 0.1 -- один кадр сдвигает время не больше чем на это (подвисания не перематывают анимацию)
local WATCHDOG_EXTRA = 4 -- сек сверх Duration + FADE_TIME: страховка по реальному времени
local FONT = Enum.Font.FredokaOne

local WHITE = Color3.new(1, 1, 1)
local NAVY = Color3.fromRGB(22, 38, 92) -- обводка: тёмно-синяя, мягче чёрной

-- Цвета фона: палитра игры (Electric / Teal / Rebirth), чуть осветлённая и «пластиковая», не неоновая
local BACKGROUND = {
	Color3.fromRGB(64, 148, 232), -- синий
	Color3.fromRGB(52, 184, 200), -- бирюзовый
	Color3.fromRGB(150, 112, 228), -- фиолетовый
	Color3.fromRGB(86, 160, 238), -- светло-синий (возврат к началу цикла)
}
local PALETTE_STEP = 1.25 -- секунд на переход к следующему цвету

-- Цвета кирпичиков-магнитов
local MAGNET_COLORS = {
	Color3.fromRGB(232, 62, 62), -- красный
	Color3.fromRGB(255, 160, 40), -- оранжевый
	Color3.fromRGB(255, 208, 52), -- жёлтый
	Color3.fromRGB(80, 204, 108), -- зелёный
	Color3.fromRGB(240, 112, 172), -- розовый
	Color3.fromRGB(244, 247, 252), -- белый
}
local SILVER = Color3.fromRGB(226, 230, 238)
local SILVER_SHADE = Color3.fromRGB(150, 158, 174)
local MAGNET_COUNT = 24
local STUD_CELL = 96 -- шаг сетки шипов, px (в масштабируемых единицах UI)
local STUD_SIZE = 56

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Плавное перетекание по палитре: t — секунды; косинусное сглаживание убирает «ступеньки» на стыках цветов.
local function paletteAt(t: number, shift: number): Color3
	local position = t / PALETTE_STEP + shift
	local index = math.floor(position)
	local f = position - index
	f = 0.5 - 0.5 * math.cos(f * math.pi)
	local a = BACKGROUND[index % #BACKGROUND + 1]
	local b = BACKGROUND[(index + 1) % #BACKGROUND + 1]
	return a:Lerp(b, f)
end

--== магнит из кирпичиков ====================================================
-- Подкова-«U»: два столбика с серебристыми наконечниками и скруглённое основание. Тень — копия формы
-- темнее и ниже на пару процентов: даёт пластиковую глубину без обводок (обводки оставляли швы на стыках).
local function part(x: number, y: number, w: number, h: number, color: Color3, corner: number, zIndex: number)
	return create("Frame")({
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,

		create("UICorner")({ CornerRadius = UDim.new(corner, 0) }),
	})
end

local function horseshoe(color: Color3, dy: number, shade: boolean, zBase: number)
	local body = if shade then darken(color, 0.38) else color
	local tip = if shade then SILVER_SHADE else SILVER
	return {
		part(0, 0.18 + dy, 0.3, 0.66, body, 0.18, zBase), -- левый столбик
		part(0.7, 0.18 + dy, 0.3, 0.66, body, 0.18, zBase), -- правый
		part(0, 0.56 + dy, 1, 0.44, body, 0.5, zBase), -- основание
		part(0, 0 + dy, 0.3, 0.26, tip, 0.2, zBase + 1), -- наконечники
		part(0.7, 0 + dy, 0.3, 0.26, tip, 0.2, zBase + 1),
	}
end

local function gloss(x: number, y: number, w: number, h: number, zIndex: number)
	return create("Frame")({
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = zIndex,

		create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
	})
end

type MagnetSpec = {
	Color: Color3,
	Size: number,
	X: number, -- доля ширины
	Y0: number, -- старт по высоте, в долях экрана (отрицательный: выше верхней кромки)
	Speed: number, -- экранов в секунду
	Rotation0: number,
	Spin: number, -- градусов в секунду
	Sway: number, -- амплитуда покачивания, px
	SwayRate: number,
	SwayPhase: number,
	Alpha: number, -- прозрачность (дальние — чуть бледнее)
}

local function newSpec(): MagnetSpec
	local size = 26 + math.random() * 62 -- 26..88 px
	local depth = (size - 26) / 62 -- 0 далеко .. 1 близко
	return {
		Color = MAGNET_COLORS[math.random(#MAGNET_COLORS)],
		Size = size,
		X = 0.03 + math.random() * 0.94,
		Y0 = -0.15 - math.random() * 1.05,
		Speed = 0.2 + depth * 0.22 + math.random() * 0.12, -- крупные ближе -> быстрее (параллакс)
		Rotation0 = math.random(-180, 180),
		Spin = (math.random() < 0.5 and -1 or 1) * (25 + math.random() * 95),
		Sway = 6 + math.random() * 24,
		SwayRate = 0.8 + math.random() * 1.6,
		SwayPhase = math.random() * math.pi * 2,
		Alpha = 0.22 * (1 - depth),
	}
end

local function Magnet(spec: MagnetSpec, elapsed: () -> number)
	local children = {}
	for _, piece in ipairs(horseshoe(spec.Color, 0.045, true, 1)) do
		table.insert(children, piece)
	end
	for _, piece in ipairs(horseshoe(spec.Color, 0, false, 3)) do
		table.insert(children, piece)
	end
	-- блики на столбиках и основании — мягкий глянец
	table.insert(children, gloss(0.06, 0.34, 0.07, 0.22, 6))
	table.insert(children, gloss(0.76, 0.34, 0.07, 0.22, 6))
	table.insert(children, gloss(0.14, 0.64, 0.7, 0.07, 6))

	local pad = 0.18 -- запас по краям: магнит целиком уходит за экран перед «перезапуском» сверху
	return create("Frame")({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(spec.Size, spec.Size),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Position = function()
			local e = elapsed()
			local y = spec.Y0 + spec.Speed * e
			if y > 1 + pad then
				-- долетел: возвращаем выше экрана (замкнутая лента длиной 1 + 2*pad)
				y = ((y + pad) % (1 + 2 * pad)) - pad
			end
			local sway = math.sin(e * spec.SwayRate + spec.SwayPhase) * spec.Sway
			return UDim2.new(spec.X, sway, y, 0)
		end,
		Rotation = function()
			local e = elapsed()
			return spec.Rotation0 + spec.Spin * e + math.sin(e * 2.1 + spec.SwayPhase) * 6
		end,

		table.unpack(children),
	})
end

--== заголовок ===============================================================
local EXTRUDE_LAYERS = 4
local EXTRUDE_STEP = 2.6 -- px глубины на слой

local function titleLabel(text: string, color: Color3, offsetY: number, zIndex: number, face: boolean)
	local props: { [any]: any } = {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, offsetY),
		Size = UDim2.fromScale(1, 1),
		Font = FONT,
		Text = text,
		TextColor3 = if face then WHITE else color, -- на лицевом слое цвет задаёт градиент
		TextScaled = true,
		ZIndex = zIndex,

		create("UITextSizeConstraint")({ MaxTextSize = 86 }),
		create("UIStroke")({
			Thickness = 6,
			Color = NAVY,
			LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	}
	if face then
		table.insert(
			props,
			create("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 246, 150)),
					ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 205, 52)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 30)),
				}),
			})
		)
	end
	return create("TextLabel")(props)
end

local function Title(elapsed: () -> number)
	local layers = {}
	-- от дальнего (нижнего, тёмного) слоя к лицевому — «выдавленная» пластиковая надпись
	for i = EXTRUDE_LAYERS, 1, -1 do
		local shade = darken(Color3.fromRGB(255, 170, 30), 0.38 + 0.04 * i)
		table.insert(layers, titleLabel(TITLE, shade, i * EXTRUDE_STEP, 10 + (EXTRUDE_LAYERS - i), false))
	end
	table.insert(layers, titleLabel(TITLE, WHITE, 0, 10 + EXTRUDE_LAYERS, true))

	return create("Frame")({
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local e = elapsed()
			-- лёгкое покачивание всего заголовка из стороны в сторону + едва заметная «плавучесть» по высоте
			return UDim2.new(0.5, math.sin(e * 1.7 + 0.5) * 9, 0.4, math.sin(e * 2.3) * 4)
		end,
		Rotation = function()
			return math.sin(elapsed() * 1.7) * 2.8
		end,
		Size = UDim2.fromScale(0.88, 0.2),
		BackgroundTransparency = 1,
		ZIndex = 10,

		create("UISizeConstraint")({ MaxSize = Vector2.new(940, 150) }),
		table.unpack(layers),
	})
end

--== полоса прогресса ========================================================
local function ProgressBar(progress: () -> number)
	return create("Frame")({
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.5, 0.06),
		BackgroundTransparency = 1,
		ZIndex = 10,

		create("UISizeConstraint")({ MinSize = Vector2.new(260, 30), MaxSize = Vector2.new(560, 40) }),

		-- дорожка: тёмно-синий пластик с белым ободком
		create("Frame")({
			Name = "Track",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = NAVY,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 10,

			create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
			create("UIStroke")({
				Thickness = 3.5,
				Color = WHITE,
				Transparency = 0.35,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
				PaddingTop = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 5),
			}),

			-- заполнение: жёлтый «кирпичик» с глянцем
			create("Frame")({
				Name = "Fill",
				Size = function()
					return UDim2.fromScale(math.max(progress(), 0.001), 1)
				end,
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 11,

				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIGradient")({
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 232, 110)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 176, 34)),
					}),
				}),
				-- блик по верхней половине
				create("Frame")({
					Position = UDim2.fromScale(0.03, 0.12),
					Size = UDim2.fromScale(0.94, 0.3),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.55,
					BorderSizePixel = 0,
					ZIndex = 12,

					create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				}),
			}),
		}),

		-- проценты под полосой
		create("TextLabel")({
			Name = "Percent",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 12),
			Size = UDim2.fromOffset(160, 40),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 34,
			TextColor3 = WHITE,
			ZIndex = 10,
			Text = function()
				return math.floor(progress() * 100 + 0.5) .. "%"
			end,

			create("UIStroke")({
				Thickness = 4,
				Color = NAVY,
				LineJoinMode = Enum.LineJoinMode.Round,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			}),
		}),
	})
end

--== фон =====================================================================
local function Background(elapsed: () -> number, guiScale: () -> number, blocking: () -> boolean)
	-- шипы (studs): сетка кругов с мягким верхним бликом; число считаем по размеру экрана в единицах UI
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local scale = math.max(guiScale(), 0.01)
	local cols = math.ceil(viewport.X / scale / STUD_CELL) + 1
	local rows = math.ceil(viewport.Y / scale / STUD_CELL) + 1

	local studs = {}
	for i = 1, cols * rows do
		table.insert(
			studs,
			create("Frame")({
				LayoutOrder = i,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,

				create("UICorner")({ CornerRadius = UDim.new(0.5, 0) }),
				create("UIGradient")({
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.0),
						NumberSequenceKeypoint.new(1, 0.6),
					}),
				}),
			})
		)
	end

	return create("Frame")({
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Active = blocking, -- не пропускаем клики в мир, пока идёт загрузка; после Duration выключается
		ZIndex = 1,

		create("UIGradient")({
			Rotation = function()
				return 58 + math.sin(elapsed() * 0.9) * 14
			end,
			Color = function()
				local t = elapsed()
				local top = paletteAt(t, 0)
				local bottom = paletteAt(t, 1.4):Lerp(WHITE, 0.12) -- нижний край светлее: глянцевый «градиент пластика»
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0, top),
					ColorSequenceKeypoint.new(0.55, top:Lerp(bottom, 0.55)),
					ColorSequenceKeypoint.new(1, bottom),
				})
			end,
		}),

		-- шипы
		create("Frame")({
			Name = "Studs",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 1,

			create("UIGridLayout")({
				CellSize = UDim2.fromOffset(STUD_SIZE, STUD_SIZE),
				CellPadding = UDim2.fromOffset(STUD_CELL - STUD_SIZE, STUD_CELL - STUD_SIZE),
				SortOrder = Enum.SortOrder.LayoutOrder,
				FillDirectionMaxCells = cols,
			}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, (STUD_CELL - STUD_SIZE) / 2),
				PaddingTop = UDim.new(0, (STUD_CELL - STUD_SIZE) / 2),
			}),
			table.unpack(studs),
		}),

		-- диагональный блик: светлая полоса медленно плывёт слева направо
		create("Frame")({
			Name = "Sheen",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local f = (elapsed() * 0.22) % 1.6 - 0.3
				return UDim2.fromScale(f, 0.5)
			end,
			Size = UDim2.fromScale(0.34, 1.8),
			Rotation = 18,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 2,

			create("UIGradient")({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.86),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),

		-- мягкая виньетка по краям: глубина без тёмной «сайфай» рамки
		create("Frame")({
			Name = "Vignette",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = NAVY,
			BorderSizePixel = 0,
			ZIndex = 2,

			create("UIGradient")({
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.82),
					NumberSequenceKeypoint.new(0.25, 1),
					NumberSequenceKeypoint.new(0.75, 1),
					NumberSequenceKeypoint.new(1, 0.7),
				}),
			}),
		}),
	})
end

--== экран ===================================================================
export type Props = {
	Duration: number?,
	OnFinished: (() -> ())?,
}

local function LoadingScreen(props: Props?)
	local duration = (props and props.Duration) or LOADING_TIME
	local onFinished = props and props.OnFinished
	local guiScale = viewportScale()

	-- секунды отрисованного времени (см. заголовок файла)
	local timeline = source(0)
	local function elapsed(): number
		return timeline()
	end
	-- 0..1 с плавным разгоном и торможением (синусоидальное сглаживание), ровно за `duration` секунд
	local function progress(): number
		local p = math.clamp(elapsed() / duration, 0, 1)
		return 0.5 - 0.5 * math.cos(p * math.pi)
	end
	local function blocking(): boolean
		return elapsed() < duration
	end
	local function fadeAmount(): number
		local f = math.clamp((elapsed() - duration) / FADE_TIME, 0, 1)
		return f * f
	end

	local specs = {}
	for i = 1, MAGNET_COUNT do
		specs[i] = newSpec()
	end
	-- крупные рисуются позже (поверх мелких): объём «ближе-дальше»
	table.sort(specs, function(a, b)
		return a.Size < b.Size
	end)
	local magnets = {}
	for i, spec in ipairs(specs) do
		magnets[i] = Magnet(spec, elapsed)
	end

	local group = create("CanvasGroup")({
		Name = "LoadingScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = fadeAmount,

		-- содержимое масштабируется общим коэффициентом интерфейса, как HUD
		create("Frame")({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = function()
				local s = guiScale()
				return UDim2.fromScale(1 / s, 1 / s)
			end,

			create("UIScale")({ Scale = guiScale }),
			Background(elapsed, guiScale, blocking),
			create("Frame")({
				Name = "Magnets",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 2,

				table.unpack(magnets),
			}),
			Title(elapsed),
			ProgressBar(progress),
		}),
	}) :: CanvasGroup

	local screenGui = create("ScreenGui")({
		Name = "Loading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000, -- поверх всего интерфейса
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		group,
	}) :: ScreenGui

	local connection: RBXScriptConnection? = nil
	local finished = false

	-- Полное снятие: отключаем кадровый источник и УДАЛЯЕМ экран (а не только останавливаем эффекты Vide).
	local function finish()
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		screenGui:Destroy()
		if onFinished then
			onFinished()
		end
	end

	-- время идёт только по реально показанным кадрам; первый кадр пропускаем (его dt включает всю загрузку до показа)
	local firstFrame = true
	connection = RunService.RenderStepped:Connect(function(dt)
		if firstFrame then
			firstFrame = false
			return
		end
		timeline(timeline() + math.min(dt, MAX_FRAME_STEP))
		if timeline() >= duration + FADE_TIME then
			finish()
		end
	end)

	-- страховка: если RenderStepped не идёт (окно свёрнуто и т.п.), экран всё равно уберётся по реальному времени
	task.delay(duration + FADE_TIME + WATCHDOG_EXTRA, finish)

	-- снаружи сняли корень Vide раньше времени — экран тоже не должен остаться
	cleanup(function()
		finished = true
		if connection then
			connection:Disconnect()
			connection = nil
		end
		screenGui:Destroy()
	end)

	return screenGui
end

return LoadingScreen
