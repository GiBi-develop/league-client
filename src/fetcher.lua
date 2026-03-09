local logger = require("logger")
local time = require("time")
local funcs = require("funcs")
local events = require("events")
local env = require("env")
local contract = require("contract")

--- Fetch all player data from Riot API and emit events.
--- Returns puuid if successful, nil otherwise.
local function do_fetch(player_id, meta, storage)
    local game_name = meta.game_name
    local tag_line = meta.tag_line
    local player_name = game_name .. "#" .. tag_line

    logger:info("Fetching player data", {player = player_id, name = player_name})

    -- Step 1: Get account by Riot ID
    local account, err = funcs.new():call("app.lc:riot_api_get_account", {
        game_name = game_name,
        tag_line = tag_line,
        region = meta.region,
    })

    if err then
        logger:error("Failed to get account", {player = player_name, error = tostring(err)})
        events.send("league_client", "fetch.failed", "/players/" .. player_id, {
            player_id = player_id,
            player_name = player_name,
            error = tostring(err),
        })
        return nil
    end

    local puuid = account.puuid
    logger:info("Account found", {player = player_name, puuid = puuid})

    -- Steps 2-5: Launch all independent API calls in parallel
    local f_sum, _ = funcs.async("app.lc:riot_api_get_summoner", {
        puuid = puuid,
        platform = meta.platform,
    })
    local f_rank, _ = funcs.async("app.lc:riot_api_get_ranked", {
        puuid = puuid,
        platform = meta.platform,
    })
    local f_ms, _ = funcs.async("app.lc:riot_api_get_mastery_score", {
        puuid = puuid,
        platform = meta.platform,
    })
    local f_mast, _ = funcs.async("app.lc:riot_api_get_mastery", {
        puuid = puuid,
        count = 5,
        platform = meta.platform,
    })

    -- Check match count from local DB while API calls are in flight (fast, no network)
    local match_count = 20
    if storage then
        local existing = storage:get_matches({puuid = puuid, limit = 1})
        if not existing or #existing < 30 then
            match_count = 50
            logger:info("Backfill mode: fetching 50 matches", {player = player_name})
        end
    end
    local f_mids, _ = funcs.async("app.lc:riot_api_get_matches", {
        puuid = puuid,
        count = match_count,
        region = meta.region,
    })

    -- Collect results (all running concurrently; each :receive() blocks until ready)
    local summoner
    if f_sum then
        local payload, ok = f_sum:channel():receive()
        if ok and payload then summoner = payload:data() end
        if not summoner then logger:warn("Failed to get summoner", {player = player_name}) end
    end

    local ranked
    if f_rank then
        local payload, ok = f_rank:channel():receive()
        if ok and payload then ranked = payload:data() end
        if not ranked then logger:warn("Failed to get ranked", {player = player_name}) end
    end

    local mastery_score
    if f_ms then
        local payload, ok = f_ms:channel():receive()
        if ok and payload then mastery_score = payload:data() end
        if not mastery_score then logger:warn("Failed to get mastery score", {player = player_name}) end
    end

    local mastery
    if f_mast then
        local payload, ok = f_mast:channel():receive()
        if ok and payload then mastery = payload:data() end
        if not mastery then logger:warn("Failed to get mastery", {player = player_name}) end
    end

    local match_ids
    if f_mids then
        local payload, ok = f_mids:channel():receive()
        if ok and payload then match_ids = payload:data() end
        if not match_ids then logger:warn("Failed to get match IDs", {player = player_name}) end
    end

    -- Step 6: Fetch match details — only NEW ones (skip cached)
    local matches = {}
    if match_ids and #match_ids > 0 then
        local new_ids = match_ids
        if storage then
            local existing = storage:check_existing_matches({match_ids = match_ids}) or {}
            new_ids = {}
            for _, mid in ipairs(match_ids) do
                if not existing[mid] then
                    table.insert(new_ids, mid)
                end
            end
            if #match_ids ~= #new_ids then
                logger:info("Match caching", {
                    player = player_name,
                    total = #match_ids,
                    cached = #match_ids - #new_ids,
                    to_fetch = #new_ids,
                })
            end
        end

        for i = 1, math.min(#new_ids, 10) do
            local match_data, m_err = funcs.new():call("app.lc:riot_api_get_match", {
                match_id = new_ids[i],
                region = meta.region,
            })

            if m_err then
                logger:warn("Failed to get match detail", {
                    match_id = new_ids[i],
                    error = tostring(m_err),
                })
            else
                table.insert(matches, match_data)
            end

            -- Small delay between match requests to avoid rate limiting
            if i < #new_ids then
                time.sleep("200ms")
            end
        end
    end

    logger:info("Player data fetched", {
        player = player_name,
        has_summoner = summoner ~= nil,
        ranked_count = ranked and #ranked or 0,
        mastery_count = mastery and #mastery or 0,
        match_count = #matches,
    })

    -- Emit combined data event
    events.send("league_client", "player.data_fetched", "/players/" .. player_id, {
        player_id = player_id,
        player_name = player_name,
        puuid = puuid,
        game_name = game_name,
        tag_line = tag_line,
        platform = meta.platform or env.get("RIOT_PLATFORM") or "EUW1",
        region = meta.region or env.get("RIOT_REGION") or "EUROPE",
        summoner = summoner,
        ranked = ranked,
        mastery = mastery,
        mastery_score = mastery_score,
        matches = matches,
        discord_notify = meta.discord_notify or false,
        discord_webhook_url = meta.discord_webhook_url,
    })

    return puuid
end

--- Quick poll: ranked data + active game status.
--- Emits player.data_fetched (ranked only) for fast rank change detection.
--- Emits player.game_started when player enters a game.
--- Returns true if a full fetch should be triggered immediately (game ended).
local function do_quick_poll(player_id, meta, puuid, storage, game_state)
    local player_name = meta.game_name .. "#" .. meta.tag_line
    local platform = meta.platform or env.get("RIOT_PLATFORM") or "EUW1"
    local region = meta.region or env.get("RIOT_REGION") or "EUROPE"

    -- Poll ranked data and emit for rank change detection
    local ranked, rank_err = funcs.new():call("app.lc:riot_api_get_ranked", {
        puuid = puuid,
        platform = platform,
    })
    if not rank_err and ranked then
        events.send("league_client", "player.data_fetched", "/players/" .. player_id, {
            player_id = player_id,
            player_name = player_name,
            puuid = puuid,
            game_name = meta.game_name,
            tag_line = meta.tag_line,
            platform = platform,
            region = region,
            ranked = ranked,
            discord_notify = meta.discord_notify or false,
            discord_webhook_url = meta.discord_webhook_url,
        })
    end

    -- Poll active game status
    local active_game, _ = funcs.new():call("app.lc:riot_api_get_active_game", {
        puuid = puuid,
        platform = platform,
    })

    local was_in_game = game_state.in_game
    local prev_game_id = game_state.game_id

    if active_game and active_game.gameId then
        -- Player is in game
        if not was_in_game or prev_game_id ~= tostring(active_game.gameId) then
            game_state.in_game = true
            game_state.game_id = tostring(active_game.gameId)
            logger:info("Player entered game", {
                player = player_name,
                game_id = active_game.gameId,
                mode = active_game.gameMode,
            })
            events.send("league_client", "player.game_started", "/players/" .. player_id, {
                player_id = player_id,
                player_name = player_name,
                puuid = puuid,
                game_id = active_game.gameId,
                game_mode = active_game.gameMode,
                queue_id = active_game.gameQueueConfigId,
                game_length = active_game.gameLength or 0,
                discord_notify = meta.discord_notify or false,
                discord_webhook_url = meta.discord_webhook_url,
            })
        end
    else
        -- Player is not in game
        if was_in_game then
            game_state.in_game = false
            game_state.game_id = nil
            logger:info("Player left game, triggering full fetch", {player = player_name})
            return true  -- signal: trigger full fetch immediately
        end
    end

    return false
end

--- Compute adaptive fetch interval based on last match time.
--- If player hasn't played in 24h → slow down to 1h.
--- If player played within 30min → speed up to 5m.
--- Otherwise → use configured interval.
local function adaptive_interval(base_interval, storage, puuid)
    if not storage or not puuid then return base_interval end
    local matches = storage:get_matches({puuid = puuid, limit = 1})
    if not matches or #matches == 0 then return base_interval end
    local last_gc = tonumber(matches[1].game_creation) or 0
    if last_gc == 0 then return base_interval end
    local now_ms = os.time() * 1000
    local age_ms = now_ms - last_gc
    local hour_ms = 3600 * 1000
    if age_ms > 24 * hour_ms then return "1h" end
    if age_ms < 0.5 * hour_ms then return "5m" end
    return base_interval
end

--- Per-player fetcher process.
--- Runs full fetch immediately on start, then on a timer.
--- Additionally runs quick polls (ranked + live game) on a shorter interval.
local function main(player_id, meta, interval)
    local player_name = meta.game_name .. "#" .. meta.tag_line
    local ranked_interval = meta.ranked_interval or "2m"

    -- Open storage for match caching
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        logger:warn("Fetcher: could not open storage, caching disabled", {error = tostring(serr)})
        storage = nil
    end

    logger:info("Fetcher started", {
        player = player_id,
        name = player_name,
        interval = interval,
        ranked_interval = ranked_interval,
        pid = process.pid(),
    })

    local evts = process.events()
    local game_state = {in_game = false, game_id = nil}

    -- Run first full fetch immediately; capture puuid for quick polls
    local known_puuid = do_fetch(player_id, meta, storage)

    -- Set up two independent timers
    local full_timer = time.after(interval)
    local quick_timer = time.after(ranked_interval)

    while true do
        local r = channel.select {
            full_timer:case_receive(),
            quick_timer:case_receive(),
            evts:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                logger:info("Fetcher stopping", {player = player_id})
                return 0
            end
        elseif r.channel == full_timer then
            known_puuid = do_fetch(player_id, meta, storage) or known_puuid
            local next_interval = adaptive_interval(interval, storage, known_puuid)
            full_timer = time.after(next_interval)
            quick_timer = time.after(ranked_interval)  -- reset quick after full
        else
            -- Quick poll: ranked + live game
            if known_puuid then
                local need_full = do_quick_poll(player_id, meta, known_puuid, storage, game_state)
                if need_full then
                    -- Game just ended — fetch immediately to capture the new match
                    known_puuid = do_fetch(player_id, meta, storage) or known_puuid
                    full_timer = time.after(interval)
                end
            end
            quick_timer = time.after(ranked_interval)
        end
    end
end

return {main = main}
