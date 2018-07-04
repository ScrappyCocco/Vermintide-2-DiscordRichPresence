return {
	run = function()
		fassert(rawget(_G, "new_mod"), "DiscordRichVermintide must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("DiscordRichVermintide", {
			mod_script       = "scripts/mods/DiscordRichVermintide/DiscordRichVermintide",
			mod_data         = "scripts/mods/DiscordRichVermintide/DiscordRichVermintide_data",
			mod_localization = "scripts/mods/DiscordRichVermintide/DiscordRichVermintide_localization"
		})
	end,
	packages = {
		"resource_packages/DiscordRichVermintide/DiscordRichVermintide"
	}
}
