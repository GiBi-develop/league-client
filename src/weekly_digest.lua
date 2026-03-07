local logger = require("logger")
local events = require("events")
local env = require("env")
local http_client = require("http_client")
local json = require("json")
local time = require("time")
local contract = require("contract")

--- Seconds until next Sunday 09:00 UTC.
local function secs_until_sunday_9am()
    local now = os.time()
    local t = os.date("!*t", now)
    -- wday: 1=Sun, 2=Mon, ..., 7=Sat
    local wday = t.wday or 1
    local hour = t.hour or 0
    local min = t.min or 0
    local sec = t.sec or 0
    local days_until_sunday = (8 - wday) % 7
    if days_until_sunday == 0 and (hour > 9 or (hour == 9 and min > 0)) then
        days_until_sunday = 7
    end
    local target_secs = days_until_sunday * 86400 + (9 - hour) * 3600 - min * 60 - sec
    if target_secs <= 0 then target_secs = 7 * 86400 end
    return target_secs
end

--- Build weekly digest embed for a player.
local function build_digest_embed(player, stats)
    local name = (player.game_name or "Unknown") .. "#" .. (player.tag_line or "")
    local wins = stats.wins or 0
    local losses = stats.losses or 0
    local games = wins + losses
    local wr = games > 0 and math.floor(wins / games * 100) or 0
    local lp_change = stats.lp_change or 0
    local lp_str = lp_change >= 0 and ("+" .. lp_change) or tostring(lp_change)
    local top_champ = stats.top_champion or "N/A"

    local color = wr >= 50 and 0x57F287 or 0xED4245

    return {
        title = name .. " — Weekly Summary",
        color = color,
        fields = {
            {name = "Games", value = tostring(games), inline = true},
            {name = "Win Rate", value = tostring(wr) .. "%", inline = true},
            {name = "LP Change", value = lp_str .. " LP", inline = true},
            {name = "Most Played", value = top_champ, inline = true},
        },
        footer = {text = "Week ending " .. os.date("!%Y-%m-%d")},
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Get weekly stats for a player from storage.
local function get_weekly_stats(storage, puuid)
    -- Get win rate history for last 7 days
    local wr_history = storage:get_winrate_history({puuid = puuid, days = 7}) or {}
    local wins = 0
    local losses = 0
    for _, day in ipairs(wr_history) do
        wins = wins + (day.wins or 0)
        losses = losses + (day.losses or 0)
    end

    -- Get LP change (first vs last entry in ranked_history, last 7 days)
    local lp_history = storage:get_ranked_history({
        puuid = puuid,
        queue_type = "RANKED_SOLO_5x5",
        limit = 200,
    }) or {}

    local lp_change = 0
    if #lp_history >= 2 then
        local newest = lp_history[1]
        local oldest = lp_history[#lp_history]
        lp_change = (newest.league_points or 0) - (oldest.league_points or 0)
    end

    -- Get top champion from recent matches (last 7 days)
    local today_stats = storage:get_today_stats({puuid = puuid})
    local top_champion = today_stats and today_stats.top_champion or "N/A"

    return {
        wins = wins,
        losses = losses,
        lp_change = lp_change,
        top_champion = top_champion,
    }
end

--- Weekly Digest main loop.
local function main()
    logger:info("Weekly digest started", {pid = process.pid()})

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        logger:error("Weekly digest: could not open storage", {error = tostring(serr)})
        return 1
    end

    local sub, err = events.subscribe("league_client")
    if err then
        logger:error("Failed to subscribe to events", {error = tostring(err)})
        return 1
    end

    local ch = sub:channel()
    local evts = process.events()

    -- Schedule first digest at next Sunday 09:00 UTC
    local wait_secs = secs_until_sunday_9am()
    logger:info("Weekly digest scheduled", {secs = wait_secs})
    local digest_timer = time.after(tostring(wait_secs) .. "s")

    -- Track players seen via events
    local tracked_players = {}

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive(),
            digest_timer:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("Weekly digest stopping")
                return 0
            end
        elseif r.channel == ch then
            local evt = r.value
            if evt.data and evt.data.puuid and evt.data.discord_notify then
                local key = evt.data.puuid
                if not tracked_players[key] then
                    tracked_players[key] = {
                        game_name = evt.data.game_name,
                        tag_line = evt.data.tag_line,
                        puuid = evt.data.puuid,
                        discord_webhook_url = evt.data.discord_webhook_url,
                    }
                end
            end
        else
            -- Digest timer fired: send weekly summary for all tracked players
            local webhook_url = env.get("DISCORD_WEBHOOK_URL")
            logger:info("Sending weekly digest")

            for _, player in pairs(tracked_players) do
                local effective_url = player.discord_webhook_url
                if not effective_url or effective_url == "" then
                    effective_url = webhook_url
                end
                if effective_url and effective_url ~= "" then
                    local stats = get_weekly_stats(storage, player.puuid)
                    local embed = build_digest_embed(player, stats)
                    local payload = json.encode({username = "League Client", embeds = {embed}})

                    local resp, post_err = http_client.post(effective_url, {
                        headers = {["Content-Type"] = "application/json"},
                        body = payload,
                        timeout = "10s",
                    })
                    if post_err then
                        logger:error("Weekly digest webhook failed", {error = tostring(post_err)})
                    elseif resp.status_code ~= 204 and resp.status_code ~= 200 then
                        logger:error("Weekly digest webhook error", {status = resp.status_code})
                    else
                        logger:info("Weekly digest sent", {player = player.game_name})
                    end
                end
            end

            -- Schedule next digest in 7 days
            digest_timer = time.after("168h")
        end
    end
end

return {main = main}
