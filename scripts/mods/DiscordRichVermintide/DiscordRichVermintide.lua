local mod = get_mod("DiscordRichVermintide")

local discordRPC = require("scripts/mods/DiscordRichVermintide/lua-discordRPC/discordRPC")
local appId = require("scripts/mods/DiscordRichVermintide/applicationId")

--[[
    Variables
--]]

local current_version = "0.33" -- Used only to print the version of the mod loaded
local last_number_of_players = 0 -- Used to store the number of current human players (0 if currently loading)
local last_loading_level_key = "" -- Used to check which level is currently being loaded

local saved_lobby_id = nil -- The lobby ID to join once the game is started, nil if not used
local is_discord_join = false -- Used to skip friends check and the host reply on join, but only if is a Discord join

-- Settings variables, being read from settings
local can_users_join_lobby_always = mod:get("can_other_people_always_join_you") -- Used to know if your Discord friends can join your lobby (when you're alone in the Keep for example)
local is_joining_from_discord_active = mod:get("is_discord_ask_to_join_enabled") -- Used to know if the user want the button "Ask to Join" on Discord

-- Variables in persistent_table, must remain saved if mod is reloaded
local discord_persistent_variables = mod:persistent_table("discord_persistent_variables", {
    last_timestamp_saved = 0, -- Used to store the time of begin of the timer
    game_started = false, -- Used to check if it's the game first start, if yes i need to check if the player want to join because Discord launched the game
    saved_host_id = "", -- Used to save who is the current host i joined, used for creating the PartyID
    saved_power = 0, -- Used to save the hero power, to update it only when is necessary
    is_benchmark_mode = false -- Used to save if the current level is the benchmark mode
})

-- Discord Presence Table (Empty on start)
local discord_presence = {
    details = mod:localize("discord_presence_starting_name"),
    largeImageKey = "loading_image"
}

--[[
    Functions
--]]

-- Function that return the current timestamp
local function set_timestamp_to_now()
    discord_persistent_variables.last_timestamp_saved = os.time()
end

-- Function that return the current player table
local function get_local_player()
    return Managers.player:local_player()
end

-- Function that return the SPProfile based on player current character
local function get_local_player_sp_profile()
    return SPProfiles[get_local_player():profile_index()]
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
    return get_local_player_sp_profile().character_name
end

-- Function that get and translate the character name
local function get_player_character_name_translated()
    return Localize(get_player_character_name())
end

-- Function that get the player career name
local function get_player_career_name()
    return get_local_player_sp_profile().careers[get_local_player():career_index()].display_name
end

-- Function that get and translate the career name
local function get_player_career_name_translated()
    return Localize(get_player_career_name())
end

-- Function that get and return the current character level
local function get_player_character_level()
    return ExperienceSettings.get_level(ExperienceSettings.get_experience(get_local_player_sp_profile().display_name))
end

-- Function that get and return the power level for the current career
local function get_player_career_power_string()
    return tostring(UIUtils.presentable_hero_power_level(BackendUtils.get_total_power_level(get_local_player_sp_profile().display_name, get_player_career_name())))
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

-- Function that return if the player is playing the prologue
local function is_player_playing_prologue()
    return get_current_level_key() == "prologue"
end

-- Function that return if the player is playing the prologue or the benchmark to remove hero power and "Ask to Join" from Discord
local function is_player_playing_special_level()
    return is_player_playing_prologue() or discord_persistent_variables.is_benchmark_mode
end

-- Function that return if the current match is private
local function is_match_private()
    return Managers.matchmaking:is_game_private()
end

-- Function that return if the user is in the modded realm or not
local function is_in_modded_realm()
    return script_data["eac-untrusted"]
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
-- It checks if Deathwish Onslaught are on to display that difficulty instead of Legend
-- ("DwOns QoL" mod required - Special thanks to @danreeves for this)
local function get_difficulty_name()
    local dw_enabled, ons_enabled = false, false
    local dwons_qol = get_mod("is-dwons-on")
    if dwons_qol then
        dw_enabled, ons_enabled = dwons_qol.get_status()
    end

    if dw_enabled or ons_enabled then -- Deathwish Onslaught modded difficulty
        return string.format(
            "%s%s%s",
            dw_enabled and "Deathwish" or "",
            dw_enabled and ons_enabled and " " or "",
            ons_enabled and "Onslaught" or ""
        )
    else -- Standard difficulty
        return Localize(DifficultySettings[Managers.state.difficulty.difficulty].display_name)
    end
end

-- Function that return the current Steam Lobby ID (used for Discord JoinKey and then to Join)
local function get_lobby_steam_id()
    return LobbyInternal.lobby_id(get_current_lobby_manager().lobby)
end

-- Function that create an unique party ID that is used to create single-use invitations (the invite is no longer valid if the map change)
local function get_unique_party_id()
    if is_current_player_host() then
        if get_local_player().peer_id ~= discord_persistent_variables.saved_host_id then -- If i'm the host, they should be equal
            mod:warning("Found two different peer_id, this should not happen :thinking:")
        end
        return (get_local_player().peer_id .. get_lobby_steam_id() .. get_current_level_key())
    else
        return (discord_persistent_variables.saved_host_id .. get_lobby_steam_id() .. get_current_level_key())
    end
end

-- Function that check if the hero power has changed, if yes update the variabile and return true, otherwise return false
local function update_saved_power()
    if is_player_playing_special_level() then -- If in a special level ignore hero power
        return
    end
    if get_player_career_power_string() ~= discord_persistent_variables.saved_power then
        discord_persistent_variables.saved_power = get_player_career_power_string()
        mod:info("Power Level changed, variabile updated")
        return true
    else
        return false
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
    -- If in modded realm, append a string that indicate it
    if is_in_modded_realm() then
        current_state = "(" .. mod:localize("discord_presence_modded_realm") .. ") "
    end
    -- Generate current_state based on current map
    if is_in_lobby() then
        current_state = current_state .. mod:localize("discord_presence_in_inn")
        large_image_text = current_lv_name
    else
        current_state = current_state .. "[" .. get_difficulty_name() .. "] " .. current_lv_name
        large_image_text = get_difficulty_name() .. " - " .. current_lv_name
    end
    -- Update the Discord Presence Details
    discord_presence = {
        details = current_state,
        state = mod:localize("discord_presence_as_career", career_name_translated),
        largeImageKey = current_lv_key,
        largeImageText = large_image_text,
        smallImageKey = get_player_career_name(),
        smallImageText = get_player_character_name_translated() .. " - " .. 
            career_name_translated .. " - " .. 
            mod:localize("discord_presence_level_string", get_player_character_level()) .. " - " .. 
            mod:localize("discord_presence_power_string", discord_persistent_variables.saved_power),
        partyId = get_unique_party_id(),
        partySize = last_number_of_players,
        partyMax = 4,
        startTimestamp = discord_persistent_variables.last_timestamp_saved,
        joinSecret = get_lobby_steam_id()
    }
    if (not is_joining_from_discord_active) or is_player_playing_special_level() then
        discord_presence.joinSecret = nil -- Remove "Ask to join" button
    end
    mod:info("Updated Discord Rich List with new data")
end

local function discord_mod_initialization()
    -- Init Discord class
    discordRPC.initialize(appId, true, "552500")
    -- Discord Rich status init
    update_rich()
    mod:info("DiscordRichVermintide loaded - ver " .. current_version)
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
    if (is_host_matchmaking() or can_users_join_lobby_always) and not is_match_private() then -- Auto-accept request
        mod:echo(mod:localize("discord_join_accept_message", username))
        discordRPC.respond(userId, "yes")
        mod:info("Sent Discord Join Reply: YES to " .. username .. " ID:" .. userId)
    else -- Otherwise Auto-refuse
        mod:echo(mod:localize("discord_join_deny_message", username))
        discordRPC.respond(userId, "no")
        mod:info("Sent Discord Join Reply: NO to " .. username .. " ID:" .. userId)
    end
end

-- Discord Callback of joinGame - Executed when the user Join from Discord
function discordRPC.joinGame(joinSecret)
    mod:echo(mod:localize("discord_joining_name"))
    mod:info("discordRPC.joinGame, enabling Discord Forced Join")
    is_discord_join = true
    if not discord_persistent_variables.game_started then -- Game not started, save the id for later
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
        state = "(" .. get_level_name(last_loading_level_key) .. ")",
        largeImageKey = "loading_image"
    }
    update_rich()
end

--[[
    Mod Hooks
--]]

-- Update the variable is_benchmark_mode if the player is in the benchmark
mod:hook_safe(StateInGameRunning, "on_enter", function (self, params)
    discord_persistent_variables.is_benchmark_mode = false
    if self._benchmark_handler then
        discord_persistent_variables.is_benchmark_mode = true
    end
end)

-- Update Discord RPC when the player is InGame (in lobby/in a mission)
mod:hook_safe(StateIngame, "on_enter", function ()
    if not discord_persistent_variables.game_started then -- First start of the game
        discord_persistent_variables.game_started = true
        if saved_lobby_id ~= nil then -- The player want to Join
            join_game_with_id(saved_lobby_id)
            saved_lobby_id = nil
        end
    end
    -- Update Discord Rich Presence
    update_saved_power()
    set_timestamp_to_now()
    update_rich_list()
    update_rich()
end)

-- Character changed, need to update the Discord rich
mod:hook_safe(CharacterSelectionStateCharacter, "_respawn_player", function ()
    mod:info("Discord Rich update for _respawn_player")
    discord_persistent_variables.saved_power = get_player_career_power_string()
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
        if discord_persistent_variables.saved_host_id ~= peer_id then
            discord_persistent_variables.saved_host_id = peer_id
        end
    end
end)

-- Called when joining a game (checked is from Discord with 'is_discord_join'), if the host is not searching and we're not host friends, we want to join anyway
mod:hook(MatchmakingStateRequestJoinGame, "rpc_matchmaking_request_join_lobby_reply", function(func, self, sender, client_cookie, host_cookie, reply_id, ...)
    if reply_id == 4 and is_discord_join then
        local old_reply = NetworkLookup.game_ping_reply[reply_id]
        is_discord_join = false
        reply_id = 1
        mod:info("(Forced Join) Reply " .. old_reply .. " changed with " .. NetworkLookup.game_ping_reply[reply_id] .. " - disabled Discord forced join")
    end

    -- Call the original function
    func(self, sender, client_cookie, host_cookie, reply_id, ...)
end)

-- Called when exiting the status MatchmakingStateRequestJoinGame, if is_discord_join is true, let's set it to false because we used it
mod:hook_safe(MatchmakingStateRequestJoinGame, "on_exit", function ()
    if is_discord_join then
        mod:info("MatchmakingStateRequestJoinGame - on_exit - disabled Discord forced join")
        is_discord_join = false
    end
end)

-- Called when exiting the inventory view, check if the hero power has changed, if yes, send it to Discord
mod:hook_safe(HeroView, "on_exit", function ()
    if update_saved_power() then
        update_rich_list()
        update_rich()
    end
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
    mod:info("DiscordRichVermintide turned off - shutdown()")
end

-- Init the mod on game start or on mods reload
mod:info("DiscordRichVermintide initialization...")
discord_mod_initialization()
