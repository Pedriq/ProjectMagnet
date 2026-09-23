--!strict
-- Тонкий запускатор интерфейса. Живёт в StarterPlayerScripts (LocalScript),
-- само UI — модули в ReplicatedStorage.ClientSource.UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Точечная нотация вместо WaitForChild: ReplicatedStorage гарантированно
-- реплицирован клиенту к моменту запуска LocalScript, а благодаря
-- статически резолвящемуся пути --!strict реально выводит типы
-- из vide/App, а не сворачивает их в `any`.
local Packages = ReplicatedStorage.Packages
local ClientSource = ReplicatedStorage.ClientSource

local vide = require(Packages.Vide)
local Knit = require(Packages.Knit)
local App = require(ClientSource.UI.App)
local Data = require(ClientSource.UI.data)
local WorldState = require(ClientSource.UI.worldState)

-- UI читает данные через Knit-сервисы — ждём старт Knit и поднимаем стор
Knit.OnStart():await()
Data.start()
WorldState.start()

-- PlayerGui - не require(), статическая типизация тут ни на что не влияет,
-- а WaitForChild остаётся уместной защитой на случай гонки при старте.
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local unmount = vide.mount(App, playerGui)

-- На случай будущего hot-reload/пересборки UI без выхода из игры
-- (например, по кастомному RemoteEvent от dev-тулинга). При обычном
-- выходе игрока из игры этот код, скорее всего, не успеет отработать
-- с пользой - весь клиентский VM в этот момент и так уничтожается.
Players.LocalPlayer.AncestryChanged:Connect(function(_, parent)
	if not parent then
		unmount()
	end
end)

-- Защита от бага: после респавна папка "UI" иногда пропадает из PlayerGui
-- (причина не найдена — ни ошибки, ни кода, который бы её удалял). Проверяем
-- после каждого нового персонажа и перемонтируем, если её нет на месте.
Players.LocalPlayer.CharacterAdded:Connect(function()
	task.defer(function()
		if not playerGui:FindFirstChild("UI") then
			warn("[InitPlayerUI] UI folder missing after respawn, remounting")
			unmount()
			unmount = vide.mount(App, playerGui)
		end
	end)
end)
