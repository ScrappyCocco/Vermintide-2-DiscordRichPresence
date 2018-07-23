local mod = get_mod("DiscordRichVermintide")

-- Mod Description and Settings
local mod_data = {
	name = "Discord Rich Presence",   -- Readable mod name
	description = mod:localize("mod_description"),   -- Mod description
	is_togglable = false,                            -- If the mod can be enabled/disabled
	is_mutator = false,                              -- If the mod is mutator
	mutator_settings = {},                           -- Extra settings, if it's mutator
}

-- Mod options widgets
mod_data.options_widgets = {
	{
		["setting_name"] = "can_other_people_always_join_you",
		["widget_type"] = "checkbox",
		["text"] = mod:localize("settings_always_join_you_title"),
		["tooltip"] = mod:localize("settings_always_join_you_tooltip"),
		["default_value"] = true
	},
	{
		["setting_name"] = "is_discord_ask_to_join_enabled",
		["widget_type"] = "checkbox",
		["text"] = mod:localize("settings_ask_to_join_enabled_title"),
		["tooltip"] = mod:localize("settings_ask_to_join_enabled_tooltip"),
		["default_value"] = true
	}
}

return mod_data