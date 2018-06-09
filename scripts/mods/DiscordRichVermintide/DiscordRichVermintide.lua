local mod = get_mod("DiscordRichVermintide")

local discordRPC = require("scripts/mods/DiscordRichVermintide/discordRPC")
local appId = require("scripts/mods/DiscordRichVermintide/applicationId")

local last_number_of_players = 0

--[[
	Variables
--]]

mod.discord_presence = {
	details = "Starting the game..."
}

--[[
	Functions
--]]

--Tell discord to update the rich presence
function update_rich()
	discordRPC.updatePresence(mod.discord_presence)
end

--Update the rich presence details
function update_rich_list()
	local currently = ""
	local current_lv_key = get_current_level_key()
	if current_lv_key == "inn_level" then
		currently = "In the lobby"
	else
		currently = "Playing " .. get_level_name(current_lv_key)
	end
	mod.discord_presence = {
		state = "as " .. get_player_career_name_translated(),
		details = currently,
		largeImageKey = current_lv_key,
		largeImageText = get_level_name(current_lv_key),
		smallImageKey = get_player_career_name().display_name,
		smallImageText = get_player_career_name_translated(),
		partySize = last_number_of_players,
		partyMax = 4
	}
end

--Update the player count
function update_rich_player_count()
	if last_number_of_players ~= 0 then
		update_rich_list()
		update_rich()
	end
end

function get_current_level_key()
	return Managers.state.game_mode:level_key()
end

function get_level_name(level_key)
	local level_settings = LevelSettings[level_key]
	return Localize(level_settings.display_name)
end

function get_player_character_name()
	local player = Managers.player:local_player()
	return SPProfiles[player:profile_index()].display_name
end

function get_player_career_name()
	local player = Managers.player:local_player()
	return SPProfiles[player:profile_index()].careers[player:career_index()]
end

function get_player_career_name_translated()
	return Localize(get_player_career_name().display_name)
end

function get_current_number_of_players()
	return Managers.player:num_human_players()
end

--[[
	Hooks
--]]

--Init Discord RPC before StateSplashScreen.on_enter
mod:hook("StateSplashScreen.on_enter", function (func, ...)
	discordRPC.initialize(appId, true)
	update_rich()
	print("DiscordRichVermintide loaded - ver 0.1")
	-- Original function
	local result = func(...)
	return result
end)

mod:hook("CharacterSelectionStateCharacter._respawn_player", function (func, ...)
	-- Original function
	func(...)

	update_rich_list()
	update_rich()
end)

--Called when being the Server
mod:hook("NetworkServer.update", function (func, ...)
	-- Original function
	func(...)
	
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		print("NetworkServer.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

--Called when being the Client
mod:hook("NetworkClient.update", function (func, ...)
	-- Original function
	func(...)
	
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		print("NetworkClient.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

--[[
	Callback
--]]

-- Call when all mods are being unloaded
mod.on_unload = function(exit_game)
	discordRPC.shutdown()
	return
end

-- Call when game state changes (e.g. StateLoading -> StateIngame)
mod.on_game_state_changed = function(status, state)
	if status == "enter" then
		if state == "StateLoading" then
			mod.discord_presence = {
				details = "Loading a map..."
			}
			update_rich()
		end
		if state == "StateIngame" then
			update_rich_list()
			update_rich()
		end
	end
	return
end

-- Call when governing settings checkbox is unchecked
mod.on_disabled = function(is_first_call)
	mod:disable_all_hooks()
end

-- Call when governing settings checkbox is checked
mod.on_enabled = function(is_first_call)
	mod:enable_all_hooks()
end
