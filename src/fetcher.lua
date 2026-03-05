local logger = require("logger")
local time = require("time")
local funcs = require("funcs")
local events = require("events")
local env = require("env")

--- Fetch all player data from Riot API and emit events.
local function do_fetch(player_id, meta)
    local game_name = meta.game_name
    local tag_line = meta.tag_line
    local player_name = game_name .. "#" .. tag_line

    logger:info("Fetching player data", {player = player_id, name = player_name})

    -- Step 1: Get account by Riot ID → PUUID
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
        return
    end

    local puuid = account.puuid
    logger:info("Account found", {player = player_name, puuid = puuid})

    -- Step 2: Get summoner data
    local summoner, sum_err = funcs.new():call("app.lc:riot_api_get_summoner", {
        puuid = puuid,
        platform = meta.platform,
    })

    if sum_err then
        logger:warn("Failed to get summoner", {player = player_name, error = tostring(sum_err)})
    end

    -- Step 3: Get ranked data
    local ranked, rank_err = funcs.new():call("app.lc:riot_api_get_ranked", {
        puuid = puuid,
        platform = meta.platform,
    })

    if rank_err then
        logger:warn("Failed to get ranked", {player = player_name, error = tostring(rank_err)})
    end

    -- Step 4: Get champion mastery (top 5)
    local mastery, mast_err = funcs.new():call("app.lc:riot_api_get_mastery", {
        puuid = puuid,
        count = 5,
        platform = meta.platform,
    })

    if mast_err then
        logger:warn("Failed to get mastery", {player = player_name, error = tostring(mast_err)})
    end

    -- Step 5: Get recent match IDs
    local match_ids, match_err = funcs.new():call("app.lc:riot_api_get_matches", {
        puuid = puuid,
        count = 5,
        region = meta.region,
    })

    if match_err then
        logger:warn("Failed to get matches", {player = player_name, error = tostring(match_err)})
    end

    -- Step 6: Fetch match details (up to 5)
    local matches = {}
    if match_ids and #match_ids > 0 then
        for i = 1, math.min(#match_ids, 5) do
            local match_data, m_err = funcs.new():call("app.lc:riot_api_get_match", {
                match_id = match_ids[i],
                region = meta.region,
            })

            if m_err then
                logger:warn("Failed to get match detail", {
                    match_id = match_ids[i],
                    error = tostring(m_err),
                })
            else
                table.insert(matches, match_data)
            end

            -- Small delay between match requests to avoid rate limiting
            time.sleep("200ms")
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
        matches = matches,
        discord_notify = meta.discord_notify or false,
    })
end

--- Per-player fetcher process.
--- Runs the fetch immediately on start, then on a timer.
local function main(player_id, meta, interval)
    local player_name = meta.game_name .. "#" .. meta.tag_line

    logger:info("Fetcher started", {
        player = player_id,
        name = player_name,
        interval = interval,
        pid = process.pid(),
    })

    local evts = process.events()

    -- Run first fetch immediately
    do_fetch(player_id, meta)

    -- Then loop on timer
    while true do
        local timer = time.after(interval)

        local r = channel.select {
            timer:case_receive(),
            evts:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                logger:info("Fetcher stopping", {player = player_id})
                return 0
            end
        else
            do_fetch(player_id, meta)
        end
    end
end

return {main = main}
