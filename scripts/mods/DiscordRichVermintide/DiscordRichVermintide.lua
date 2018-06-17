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
local is_discord_join = false -- Used to skip friends check on join, but only if is a Discord join

local saved_host_id = "" -- Used to save who is the current host i joined, used for creating the PartyID

-- Settings variables, being read from settings
local can_users_join_lobby_always = mod:get("can_other_people_always_join_you") -- Used to know if random people can join your lobby (when you're alone in the keep for example)
local is_joining_from_discord_active = mod:get("is_discord_ask_to_join_enabled") -- Used to know if the user want the button "Ask to Join" on Discord

-- Discord Presence Table (Empty on start)
local discord_presence = {
	details = mod:localize("discord_presence_starting_name")
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

-- Function that return if the current host is looking for players or not
local function is_host_matchmaking()
	return get_local_player().network_manager.matchmaking_manager:is_game_matchmaking()
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

-- Function that return the current Steam Lobby ID (used for Discord JoinKey and then to Join)
local function get_lobby_steam_id()
	return LobbyInternal.lobby_id(get_current_lobby_manager().lobby)
end

-- Function that create an unique party is that is used to create single-use invitations
local function get_unique_party_id()
	if is_current_player_host() then
		if get_local_player().peer_id ~= saved_host_id then -- If i'm the host, they should be equal
			mod:warning("Found two different peer_id, this should not happen :thinking:")
		end
		return (get_local_player().peer_id .. get_lobby_steam_id() .. get_current_level_key())
	else
		return (saved_host_id .. get_lobby_steam_id() .. get_current_level_key())
	end
end

--[[
	Discord Rich Functions
--]]

-- Tell Discord to update the rich presence
local function update_rich()
	discordRPC.updatePresence(discord_presence)
	mod:info("Sent to Discord the updated discord_presence")
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
		current_state = mod:localize("discord_presence_in_inn")
		large_image_text = current_lv_name
	else
		current_state = "[" .. get_difficulty_name() .. "] " .. current_lv_name
		large_image_text = get_difficulty_name() .. " - " .. current_lv_name
	end
	-- Update the Discord Presence Details
	discord_presence = {
		details = current_state,
		state = mod:localize("discord_presence_as_career", career_name_translated),
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
	if not is_joining_from_discord_active then
		discord_presence.joinSecret = nil
	end
	mod:info("Updated Discord Rich List with new data")
end

--[[
	Discord Rich Join Functions
--]]

-- Function that join a game
local function join_game_with_id(lobby_id)
	mod:info("Joining game...")
	get_local_player().network_manager.matchmaking_manager:request_join_lobby({id=lobby_id,  is_server_invite=false} , { friend_join = true })
end

-- Discord Callback of joinRequest - Executed when an user press "Ask to Join" on Discord
function discordRPC.joinRequest(userId, username)
	if is_host_matchmaking() or can_users_join_lobby_always then -- Auto-accept request
		mod:echo(mod:localize("discord_join_accept_message", username))
		discordRPC.respond(userId, "yes")
		mod:info("Sent Discord Join Reply: YES to " .. username .. " ID:" .. userId)
	else -- Otherwise Auto-refuse
		mod:echo(mod:localize("discord_join_deny_message", username))
		discordRPC.respond(userId, "no")
		mod:info("Sent Discord Join Reply: NO to " .. username .. " ID:" .. userId)
	end
end

-- Discord Callback of joinGame - Executed when the user Join
function discordRPC.joinGame(joinSecret)
	mod:echo(mod:localize("discord_joining_name"))
	mod:info("discordRPC.joinGame, enabling Discord Forced Join")
	is_discord_join = true
	if not game_started then -- Game not started, save the id for later
		saved_lobby_id = joinSecret
		mod:info("Saved joinSecret for later, game is starting...")
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

-- Update Discord rich level loading status
local function update_rich_with_loading_level()
	discord_presence = {
		details = mod:localize("discord_presence_loading_level"),
		state = "(" .. get_level_name(last_loading_level_key) .. ")"
	}
	update_rich()
end

--[[
	Mod Hooks
--]]

-- Init Discord RPC on StateSplashScreen.on_enter
mod:hook_safe(StateSplashScreen, "on_enter", function ()
	-- Init Discord class
	discordRPC.initialize(appId, true, "552500")
	-- Discord Rich status init
	update_rich()
	mod:info("DiscordRichVermintide loaded - ver " .. current_version)
end)

-- Update Discord RPC when the player is InGame (in lobby/in a mission)
mod:hook_safe(StateIngame, "on_enter", function ()
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

-- Character changed, need to update the Discord rich
mod:hook_safe(CharacterSelectionStateCharacter, "_respawn_player", function ()
	update_rich_list()
	update_rich()
end)

-- Called when loading a map, show on Discord the map you are loading
mod:hook_safe(StateLoadingRunning, "on_enter", function (self, params)
	last_loading_level_key = params.level_transition_handler:get_next_level_key()
	update_rich_with_loading_level()
end)

-- Called when the state loading get updated, check if the get_next_level_key() changed
mod:hook_safe(StateLoadingRunning, "update", function (self)
	if last_loading_level_key ~= self.parent:get_next_level_key() then
		last_loading_level_key = self.parent:get_next_level_key()
		update_rich_with_loading_level()
	end
end)

-- Called when being the Server
mod:hook_safe(NetworkServer, "update", function ()
	-- Check if the last_number_of_players has changed, if yes update Discord rich
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		mod:info("NetworkServer.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

-- Called when being the Client
mod:hook_safe(NetworkClient, "update", function ()
	-- Check if the last_number_of_players has changed, if yes update Discord rich
	if last_number_of_players ~= get_current_number_of_players() then
		last_number_of_players = get_current_number_of_players()
		mod:info("NetworkClient.update - Result " .. last_number_of_players)
		update_rich_player_count()
	end
end)

-- Called when Joining a Game as client, the party leader change, need to save the peer_id for the partyID
mod:hook_safe(PartyManager, "set_leader", function (self_, peer_id)
	if peer_id ~= nil then
		if saved_host_id ~= peer_id then
			saved_host_id = peer_id
		end
	end
end)

-- Called when joining a game (checked is from Discord with 'is_discord_join'), if the host is not searching and we're not host friends, we want to join anyway
mod:hook(MatchmakingStateRequestJoinGame, "rpc_matchmaking_request_join_lobby_reply", function(func, self, sender, client_cookie, host_cookie, reply_id, ...)
	if reply_id == 4 and is_discord_join then
		local old_reply = NetworkLookup.game_ping_reply[reply_id]
		is_discord_join = false
		reply_id = 1
		mod:info("Reply " .. old_reply .. " changed with " .. NetworkLookup.game_ping_reply[reply_id])
	end

	-- Call the original function
	func(self, sender, client_cookie, host_cookie, reply_id, ...)
end)

-- Called when Joining a game, if the join fails, we disable 'is_discord_join' to not force non-Discord joins
mod:hook_safe(MatchmakingStateRequestJoinGame, "_join_game_failed", function ()
	mod:info("Join Failed, disabling Discord Forced Join")
	is_discord_join = false
end)

--[[
	Callback
--]]

-- Called on every update to mods
mod.update = function()
	discordRPC.runCallbacks()
end

-- Called when the mod settings changes
mod.on_setting_changed = function(setting_name)
	if setting_name == "can_other_people_always_join_you" then
		can_users_join_lobby_always = mod:get(setting_name)
	end
	if setting_name == "is_discord_ask_to_join_enabled" then
		is_joining_from_discord_active = mod:get(setting_name)
		update_rich_list()
		update_rich()
	end
end

-- Call when all mods are being unloaded, shutdown Discord rich
mod.on_unload = function()
	discordRPC.shutdown()
end
