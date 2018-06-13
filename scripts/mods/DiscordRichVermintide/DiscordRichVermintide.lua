local mod = get_mod("DiscordRichVermintide")

local discordRPC = require("scripts/mods/DiscordRichVermintide/lua-discordRPC/discordRPC")
local appId = require("scripts/mods/DiscordRichVermintide/applicationId")

--[[
	Variables
--]]

local current_version = "0.30" -- Used only to print the version of the mod loaded
local last_number_of_players = 0 -- Used to store the number of current human players (0 if currently loading)
local last_timestamp_saved = 0 -- Used to store the time of begin of the timer
local last_loading_level_key = "" -- Used to check which level is currently being loaded

local discord_presence = {
	details = "Starting the game..."
}

--[[
	Discord Rich Join Functions
--]]

function discordRPC.joinRequest(userId, username, discriminator, avatar)
	print("discordRPC.joinRequest")
	mod:echo("discordRPC.joinRequest")
    print(string.format("Discord: join request (%s, %s, %s, %s)", userId, username, discriminator, avatar))
	discordRPC.respond(userId, "yes")
end

function discordRPC.joinGame(joinSecret)
	print("discordRPC.joinGame")
	mod:echo("discordRPC.joinGame")
	print(string.format("Discord: join (%s)", joinSecret))
end

--[[
	Functions
--]]

-- Function that return the current timestamp
local function set_timestamp_to_now()
	last_timestamp_saved = os.time()
end

-- Function that return the current level key
local function get_current_level_key()
	return Managers.state.game_mode:level_key()
end

-- Function that get the level name from the level key
local function get_level_name(level_key)
	return Localize(LevelSettings[level_key].display_name)
end

-- Function that get the player character name
local function get_player_character_name()
	return SPProfiles[Managers.player:local_player():profile_index()].character_name
end

-- Function that get and translate the character name
local function get_player_character_name_translated()
	return Localize(get_player_character_name())
end

-- Function that get the player career name
local function get_player_career_name()
	local player = Managers.player:local_player()
	return SPProfiles[player:profile_index()].careers[player:career_index()]
end

-- Function that get and translate the career name
local function get_player_career_name_translated()
	return Localize(get_player_career_name().display_name)
end

-- Function that get the number of current human players
local function get_current_number_of_players()
	return Managers.player:num_human_players()
end

local function is_current_player_host()
	return Managers.state.game_mode.is_server
end

local function get_player_unique_id()
	return Managers.player:local_player()._unique_id
end

-- Function that return if the current level is the lobby
local function is_in_lobby()
	return get_current_level_key() == "inn_level"
end

local function get_network_hash()
	if is_current_player_host() then
		return Managers.state.game_mode._lobby_host.network_hash
	else
		return Managers.state.game_mode._lobby_client.network_hash
	end
end

-- Function that return the difficulty localized string
local function get_difficulty_name()
	return Localize(DifficultySettings[Managers.state.difficulty.difficulty].display_name)
end

--[[
	Discord Rich Functions
--]]

-- Tell discord to update the rich presence
local function update_rich()
	discordRPC.updatePresence(discord_presence)
end

-- Update the rich presence details
local function update_rich_list()
	local currently = ""
	local current_lv_key = get_current_level_key()
	local career_name_translated = get_player_career_name_translated()
	if is_in_lobby() then
		currently = "In the lobby"
	else
		currently = "[" .. get_difficulty_name() .. "] " .. get_level_name(current_lv_key)
	end
	discord_presence = {
		details = currently,
		state = "as " .. career_name_translated,
		largeImageKey = current_lv_key,
		largeImageText = get_level_name(current_lv_key),
		smallImageKey = get_player_career_name().display_name,
		smallImageText = get_player_character_name_translated() .. " - " .. career_name_translated,
		partyId = get_player_unique_id(),
		partySize = last_number_of_players,
		partyMax = 4,
		startTimestamp = last_timestamp_saved,
		joinSecret = get_network_hash()
	}
end

--[[
	Discord Rich Status Update Functions
--]]

-- Update the player count
local function update_rich_player_count()
	if last_number_of_players ~= 0 then
		update_rich_list()
		update_rich()
	end
end

-- Update discord rich level loading status
local function update_rich_with_loading_level()
	discord_presence = {
		details = "Loading a map...",
		state = "(" .. get_level_name(last_loading_level_key) .. ")"
	}
	update_rich()
end

--[[
	Mod Hooks
--]]

-- Init Discord RPC on StateSplashScreen.on_enter
mod:hook_safe(StateSplashScreen, "on_enter", function (...)
	discordRPC.initialize(appId, true, "552500")
	update_rich()
	print("DiscordRichVermintide loaded - ver " .. current_version)
end)

-- Character changed, need to update the discord rich
mod:hook_safe(CharacterSelectionStateCharacter, "_respawn_player", function (...)
	update_rich_list()
	update_rich()
end)

-- Called when loading a map, show on discord the map you are loading
mod:hook(StateLoadingRunning, "on_enter", function (func, self, params)
	last_loading_level_key = params.level_transition_handler:get_next_level_key()
	update_rich_with_loading_level()
	
	-- Call the original function
	func(self, params)
end)

-- Called when the state loading get updated, check if the get_next_level_key() changed
mod:hook(StateLoadingRunning, "update", function (func, self, ...)
	if last_loading_level_key ~= self.parent:get_next_level_key() then
		last_loading_level_key = self.parent:get_next_level_key()
		update_rich_with_loading_level()
	end
	
	-- Call the original function
	func(self, ...)
end)

-- Called when being the Server
mod:hook_safe(NetworkServer, "update", function (...)
	-- Check if the last_number_of_players has changed, if yes update discord rich
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		print("NetworkServer.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

-- Called when being the Client
mod:hook_safe(NetworkClient, "update", function (...)
	-- Check if the last_number_of_players has changed, if yes update discord rich
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		print("NetworkClient.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

--[[
	Callback
--]]

-- Called on every update to mods
-- dt - time in milliseconds since last update
mod.update = function(dt)
	discordRPC.runCallbacks()
end

-- Call when game state changes (e.g. StateLoading -> StateIngame)
mod.on_game_state_changed = function(status, state)
	if status == "enter" then
		if state == "StateIngame" then -- Player has joined a map
			set_timestamp_to_now()
			update_rich_list()
			update_rich()
		end
	end
end

-- Call when all mods are being unloaded, shutdown discord rich
mod.on_unload = function(exit_game)
	discordRPC.shutdown()
end
