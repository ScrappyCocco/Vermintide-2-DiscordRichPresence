local mod = get_mod("DiscordRichVermintide")

-- Mod Description and Settings
local mod_data = {
	name = "Vermintide 2 - Discord Rich Presence",                               -- Readable mod name
	description = "Discord Rich Vermintide is a Vermintide 2 mods that show on Discord the character you are playing and what are you doing",  -- Mod description
	is_togglable = false,                            -- If the mod can be enabled/disabled
	is_mutator = false,                             -- If the mod is mutator
	mutator_settings = {},                          -- Extra settings, if it's mutator
}

-- Mod options widgets
mod_data.options_widgets = {
	{
		["setting_name"] = "can_other_people_always_join_you",
		["widget_type"] = "checkbox",
		["text"] = "Let others join without a Discord invitation",
		["tooltip"] = "Let others join your lobby even if you're doing your things alone and you aren't open for other players (in the Keep for example).\n" ..
			"(Remember that only your Discord friends can click 'Ask to Join') \n\n" ..
			"If you deactivate this, you have to send a chat invite in Discord to let people join your lobby before a game. \n\n" ..
			"This doesn't block other people joining your game if it's open (during matchmaking or during a non-private game) \n\n",
		["default_value"] = true
	},
	{
		["setting_name"] = "is_discord_ask_to_join_enabled",
		["widget_type"] = "checkbox",
		["text"] = "Ask To Join button on Discord",
		["tooltip"] = "If you want the 'Ask To Join' button on your Discord profile while in game, if you remove it, you can't invite people from Discord. \n\n" ..
			"You can still join other people from Discord",
		["default_value"] = true
	}
}

return mod_data