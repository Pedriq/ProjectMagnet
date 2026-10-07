local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.Vide)

local Panel = require(ReplicatedStorage.ClientSource.UI.components.Panel)
local VolumeSlider = require(ReplicatedStorage.ClientSource.UI.components.VolumeSlider)
local Theme = require(ReplicatedStorage.ClientSource.UI.theme)
local AudioSettings = require(ReplicatedStorage.ClientSource.audioSettings)

local create = vide.create

--[[
	SettingsPanel — окно настроек. Пока только звук:

	  ┌─ Settings ──────────────────────────── [✕] ┐
	  │  Music                              70%    │
	  │  ████████●──────────────                   │
	  │  Sound Effects                      100%   │
	  │  ████████████████████●                     │
	  └────────────────────────────────────────────┘

	Громкость применяется сразу (audioSettings -> SoundGroup Music / SFX).
	Открывается иконкой Settings в верхней панели (TopbarPlus, см. HUD).

	Использование: SettingsPanel({ OnClose = fn }) -> () -> Instance (для vide.switch в HUD).
]]

export type Props = {
	OnClose: () -> (),
	OnVolumeCommitted: ((kind: "Music" | "Sfx", value: number) -> ())?, -- громкость зафиксирована: сохранить на сервере
}

local function SettingsPanel(props: Props)
	return function()
		return Panel({
			ZIndex = 10,
			Size = UDim2.fromOffset(460, 362),
			OnClose = props.OnClose,

			Title = "Settings",
			TitleColor = Theme.titleColor("Electric"),
			TitleTransparency = 0,
			BodyColor = Theme.bodyColor("Electric"),
			BodyTransparency = Theme.PanelBodyTransparency,
			StrokeColor = Theme.Outline,
			TitleImage = Theme.PanelTitleTexture,
			TitleImageTransparency = Theme.PanelTitleTextureTransparency,
			StrokeThickness = Theme.PanelStrokeThickness,

			List = false,

			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 16),
			}),

			VolumeSlider({
				LayoutOrder = 1,
				Label = "Music",
				Color = Theme.ButtonElectric,
				Value = AudioSettings.musicVolume,
				OnChanged = AudioSettings.setMusic,
				OnCommitted = function(v)
					if props.OnVolumeCommitted then
						props.OnVolumeCommitted("Music", v)
					end
				end,
			}),
			VolumeSlider({
				LayoutOrder = 2,
				Label = "Sound Effects",
				Color = Theme.ButtonMoney,
				Value = AudioSettings.sfxVolume,
				OnChanged = AudioSettings.setSfx,
				OnCommitted = function(v)
					if props.OnVolumeCommitted then
						props.OnVolumeCommitted("Sfx", v)
					end
				end,
			}),
		})
	end
end

return SettingsPanel
