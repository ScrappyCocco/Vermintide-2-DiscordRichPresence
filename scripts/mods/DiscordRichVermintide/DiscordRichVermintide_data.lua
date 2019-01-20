local mod = get_mod("DiscordRichVermintide")

-- Mod Description and Settings
return {
    name = "Discord Rich Presence", -- Mod Name
    description = mod:localize("mod_description"), -- Mod description
    options = {
        widgets = {
            {
                setting_id = "can_other_people_always_join_you",
                type = "checkbox",
                default_value = true
            },
            {
                setting_id = "is_discord_ask_to_join_enabled",
                type = "checkbox",
                default_value = true
            }
        }
    }
}
