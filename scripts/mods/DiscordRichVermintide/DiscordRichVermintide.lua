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

local game_started = false -- Used to check if it's the game first start, if yes i need to check if the player want to join because Discord launched the game
local saved_lobby_id = nil -- The lobby ID to join once the game is started, nil if not used

local saved_host_id = "" -- Used to save who is the current host i joined, used for creating the PartyID

local discord_presence = {
	details = "Starting the game..."
}

--[[
	Functions
--]]

-- Function that return the current timestamp
local function set_timestamp_to_now()
	last_timestamp_saved = os.time()
end

-- Function that return the current player table
local function get_local_player()
	return Managers.player:local_player()
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
	return SPProfiles[get_local_player():profile_index()].character_name
end

-- Function that get and translate the character name
local function get_player_character_name_translated()
	return Localize(get_player_character_name())
end

-- Function that get the player career name
local function get_player_career_name()
	local player = get_local_player()
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

-- Function that return if the current player is the host
local function is_current_player_host()
	return Managers.state.game_mode.is_server
end

-- Function that return if the current level is the lobby
local function is_in_lobby()
	return get_local_player().network_manager.matchmaking_manager._ingame_ui.is_in_inn
end

-- Function that return if the current match is private
local function is_match_private()
	return Managers.matchmaking:is_game_private()
end

-- Function that return the lobby manager based if the player is host or not
local function get_current_lobby_manager()
	if is_current_player_host() then
		return Managers.state.game_mode._lobby_host
	else
		return Managers.state.game_mode._lobby_client
	end
end

-- Function that return the difficulty localized string
local function get_difficulty_name()
	return Localize(DifficultySettings[Managers.state.difficulty.difficulty].display_name)
end

-- Function that return the current Steam Lobby ID (used to Join)
local function get_lobby_steam_id()
	return LobbyInternal.lobby_id(get_current_lobby_manager().lobby)
end

-- Function that create an unique party is that is used to create single-use invitations
local function get_unique_party_id()
	if is_current_player_host() then
		if get_local_player().peer_id ~= saved_host_id then
			print("An error occurred with the peer_id")
		end
		return (get_local_player().peer_id .. get_lobby_steam_id() .. get_current_level_key())
	else
		return (saved_host_id .. get_lobby_steam_id() .. get_current_level_key())
	end
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
	local current_state = ""
	local large_image_text = ""
	local current_lv_key = get_current_level_key()
	local current_lv_name = get_level_name(current_lv_key)
	local career_name_translated = get_player_career_name_translated()
	-- Generate current_state based on current map
	if is_in_lobby() then
		current_state = "In the lobby"
		large_image_text = current_lv_name
	else
		current_state = "[" .. get_difficulty_name() .. "] " .. current_lv_name
		large_image_text = get_difficulty_name() .. " - " .. current_lv_name
	end
	-- Update the Discord Presence Details
	discord_presence = {
		details = current_state,
		state = "as " .. career_name_translated,
		largeImageKey = current_lv_key,
		largeImageText = large_image_text,
		smallImageKey = get_player_career_name().display_name,
		smallImageText = get_player_character_name_translated() .. " - " .. career_name_translated,
		partyId = get_unique_party_id(),
		partySize = last_number_of_players,
		partyMax = 4,
		startTimestamp = last_timestamp_saved,
		joinSecret = get_lobby_steam_id()
	}
end

--[[
	Discord Rich Join Functions
--]]

-- Function that join a game
local function join_game_with_id(lobby_id)
	get_local_player().network_manager.matchmaking_manager:request_join_lobby({id=lobby_id,  is_server_invite=false} , { friend_join = true })
end

-- Discord Callback of joinRequest - Executed when an user press "Ask to Join" on Discord
function discordRPC.joinRequest(userId, username, discriminator, avatar)
	if get_current_number_of_players() == 4 or is_match_private() then
		mod:echo("You automatically refused " .. username .. " join request")
		discordRPC.respond(userId, "no")
	else
		mod:echo(username .. " is joining you from Discord")
		discordRPC.respond(userId, "yes")
	end
end

-- Discord Callback of joinGame - Executed when the user Join
function discordRPC.joinGame(joinSecret)
	mod:echo("Discord RPC - Joining Game...")
	if not game_started then -- Game not started, save the id for later
		saved_lobby_id = joinSecret
	else -- Join now
		join_game_with_id(joinSecret)
	end
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

-- Update Discord RPC when the player is InGame (in lobby/in a mission)
mod:hook_safe(StateIngame, "on_enter", function (...)
	if not game_started then -- First start of the game
		game_started = true
		if saved_lobby_id ~= nil then -- The player want to Join
			join_game_with_id(saved_lobby_id)
			saved_lobby_id = nil
		end
	end
	--Update Discord Rich Presence
	set_timestamp_to_now()
	update_rich_list()
	update_rich()
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

-- Called when Joining a Game as client, the party leader change, need to save the peer_id for the partyID
mod:hook(PartyManager, "set_leader", function (func, self, peer_id)
	if peer_id ~= nil then
		if saved_host_id ~= peer_id then
			saved_host_id = peer_id
		end
	end
	
	-- Call the original function
	func(self, peer_id)
end)

--[[
	Callback
--]]

-- Called on every update to mods
-- dt - time in milliseconds since last update
mod.update = function(dt)
	discordRPC.runCallbacks()
end

-- Call when all mods are being unloaded, shutdown discord rich
mod.on_unload = function(exit_game)
	discordRPC.shutdown()
end
