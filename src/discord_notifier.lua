local logger = require("logger")
local events = require("events")
local env = require("env")
local http_client = require("http_client")
local json = require("json")
local contract = require("contract")
local time = require("time")

--- Format damage number (e.g. 23456 → "23.5k")
local function fmt_number(n)
    if not n then return "0" end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

--- Compute KDA ratio string
local function kda_ratio(k, d, a)
    k = k or 0
    d = d or 0
    a = a or 0
    if d == 0 then return "Perfect" end
    return string.format("%.1f", (k + a) / d)
end

--- Map queue_id to a human-readable name.
local function queue_label(queue_id, game_mode)
    if queue_id == 420 then return "Solo/Duo"
    elseif queue_id == 440 then return "Flex"
    elseif queue_id == 450 then return "ARAM"
    elseif queue_id == 900 then return "ARURF"
    elseif queue_id == 1700 then return "Arena"
    elseif queue_id == 490 then return "Quick Play"
    end
    return game_mode or "Classic"
end

--- Build a Discord embed for live game started.
local function build_game_embed(data)
    local queue_name = queue_label(data.queue_id, data.game_mode)
    local fields = {
        {name = "Queue", value = queue_name, inline = true},
    }
    if data.game_length and data.game_length > 60 then
        local min = math.floor(data.game_length / 60)
        table.insert(fields, {name = "In Progress", value = tostring(min) .. " min", inline = true})
    end
    return {
        title = data.player_name .. " — In Game",
        color = 0xED4245,
        fields = fields,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Build a Discord embed for goal achieved.
local function build_goal_embed(data)
    local tier_str = (data.current_tier or "") .. " " .. (data.current_rank or "") .. " " .. tostring(data.current_lp or 0) .. "LP"
    local queue_name = data.queue_type == "RANKED_SOLO_5x5" and "Solo/Duo"
        or data.queue_type == "RANKED_FLEX_SR" and "Flex"
        or data.queue_type or "Ranked"
    return {
        title = data.player_name .. " — Goal Achieved!",
        color = 0xFFD700,
        fields = {
            {name = "Goal", value = data.target_value or "", inline = true},
            {name = "Queue", value = queue_name, inline = true},
            {name = "Current Rank", value = "`" .. tier_str .. "`", inline = true},
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Build a Discord embed for rank change.
local function build_rank_embed(data)
    local old_rank = data.old_tier .. " " .. data.old_rank .. " " .. tostring(data.old_lp) .. "LP"
    local new_rank = data.new_tier .. " " .. data.new_rank .. " " .. tostring(data.new_lp) .. "LP"

    local lp_diff = (data.new_lp or 0) - (data.old_lp or 0)
    local lp_str = ""
    if data.old_tier == data.new_tier and data.old_rank == data.new_rank then
        if lp_diff > 0 then
            lp_str = " (+" .. tostring(lp_diff) .. " LP)"
        elseif lp_diff < 0 then
            lp_str = " (" .. tostring(lp_diff) .. " LP)"
        end
    end

    local winrate = 0
    local wins = tonumber(data.wins) or 0
    local losses = tonumber(data.losses) or 0
    local total = wins + losses
    if total > 0 then
        winrate = math.floor(wins / total * 100)
    end

    local color = lp_diff >= 0 and 0x57F287 or 0xED4245
    local queue_name = data.queue_type == "RANKED_SOLO_5x5" and "Solo/Duo"
        or data.queue_type == "RANKED_FLEX_SR" and "Flex"
        or data.queue_type or "Ranked"

    return {
        title = data.player_name .. " — Rank Update" .. lp_str,
        color = color,
        fields = {
            {name = "Queue", value = queue_name, inline = true},
            {name = "Previous", value = "`" .. old_rank .. "`", inline = true},
            {name = "Current", value = "`" .. new_rank .. "`", inline = true},
            {name = "Win Rate", value = tostring(winrate) .. "% (" .. tostring(wins) .. "W " .. tostring(losses) .. "L)", inline = true},
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Build a Discord embed for new match with full stats.
local function build_match_embed(data)
    local k = data.kills or 0
    local d = data.deaths or 0
    local a = data.assists or 0
    local kda_str = tostring(k) .. "/" .. tostring(d) .. "/" .. tostring(a)
    local kda_r = kda_ratio(k, d, a)
    local result = data.win and "Victory" or "Defeat"
    local color = data.win and 0x57F287 or 0xED4245

    local pos = data.position or ""
    if pos == "UTILITY" then pos = "SUPPORT"
    elseif pos == "" then pos = "—"
    end

    -- LP diff string for title
    local lp_str = ""
    if data.lp_diff then
        if data.lp_diff > 0 then
            lp_str = " (+" .. tostring(data.lp_diff) .. " LP)"
        elseif data.lp_diff < 0 then
            lp_str = " (" .. tostring(data.lp_diff) .. " LP)"
        end
    end

    local fields = {
        {name = "Champion", value = data.champion_name or "Unknown", inline = true},
        {name = "KDA", value = "`" .. kda_str .. "` (" .. kda_r .. ")", inline = true},
        {name = "Position", value = pos, inline = true},
        {name = "CS", value = tostring(data.cs or 0) .. " (" .. tostring(data.cs_per_min or 0) .. "/min)", inline = true},
        {name = "Damage", value = fmt_number(data.total_damage), inline = true},
        {name = "Gold", value = fmt_number(data.gold_earned), inline = true},
        {name = "Vision", value = tostring(data.vision_score or 0), inline = true},
        {name = "Duration", value = data.game_duration or "—", inline = true},
    }

    -- Add LP field if available
    if data.lp_diff then
        local lp_value = data.lp_diff > 0
            and "+" .. tostring(data.lp_diff) .. " LP"
            or tostring(data.lp_diff) .. " LP"
        table.insert(fields, {name = "LP", value = "`" .. lp_value .. "`", inline = true})
    end

    -- Build op.gg match URL from match_id (format: PLATFORM_MATCHID)
    local match_url = nil
    if data.match_id then
        local mid = tostring(data.match_id)
        -- Extract platform prefix (e.g. "RU_123456" -> "ru")
        local platform_prefix = string.match(mid, "^([^_]+)")
        if platform_prefix then
            match_url = "https://www.op.gg/matches/" .. string.lower(platform_prefix) .. "/" .. mid
        end
    end

    return {
        title = data.player_name .. " — " .. result .. lp_str,
        color = color,
        url = match_url,
        fields = fields,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Send an embed to Discord via webhook. Returns true on success, false on failure.
local function send_webhook(webhook_url, embed)
    local payload = json.encode({
        username = "League Client",
        embeds = {embed},
    })

    local resp, err = http_client.post(webhook_url, {
        headers = {["Content-Type"] = "application/json"},
        body = payload,
        timeout = "10s",
    })

    if err then
        logger:error("Discord webhook request failed", {error = tostring(err)})
        return false, payload
    end

    if resp.status_code ~= 204 and resp.status_code ~= 200 then
        logger:error("Discord webhook returned error", {
            status = resp.status_code,
            body = resp.body,
        })
        return false, payload
    end

    logger:debug("Discord notification sent")
    return true, payload
end

--- Retry pending notifications from queue (#11).
local function retry_queued(storage)
    if not storage then return end
    local pending = storage:get_pending_notifications({limit = 5})
    if not pending or #pending == 0 then return end

    for _, item in ipairs(pending) do
        local resp, err = http_client.post(tostring(item.webhook_url), {
            headers = {["Content-Type"] = "application/json"},
            body = tostring(item.payload),
            timeout = "10s",
        })

        local success = not err and (resp.status_code == 204 or resp.status_code == 200)
        storage:update_notification_attempt({
            id = item.id,
            attempts = (item.attempts or 0) + 1,
            success = success,
        })

        if success then
            logger:info("Retried notification delivered", {id = item.id})
        end
    end
end

--- Discord Notifier main loop.
local function main()
    logger:info("Discord notifier started", {pid = process.pid()})

    local webhook_url = env.get("DISCORD_WEBHOOK_URL")
    if not webhook_url or webhook_url == "" then
        logger:warn("DISCORD_WEBHOOK_URL not set, notifier will idle")
    end

    -- Open storage for notification retry queue (#11)
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        logger:warn("Discord notifier: could not open storage, retry queue disabled", {error = tostring(serr)})
        storage = nil
    end

    local sub, err = events.subscribe("league_client")
    if err then
        logger:error("Failed to subscribe to events", {error = tostring(err)})
        return 1
    end

    local ch = sub:channel()
    local evts = process.events()
    local retry_timer = time.after("5m")

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive(),
            retry_timer:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("Discord notifier stopping")
                return 0
            end
        elseif r.channel == retry_timer then
            retry_queued(storage)
            retry_timer = time.after("5m")
        else
            local evt = r.value

            webhook_url = env.get("DISCORD_WEBHOOK_URL")

            -- Only send Discord notifications for players with discord_notify enabled
            if not evt.data.discord_notify then
                goto continue
            end

            -- Per-player webhook overrides global (#10)
            local effective_url = evt.data.discord_webhook_url
            if not effective_url or effective_url == "" then
                effective_url = webhook_url
            end
            if not effective_url or effective_url == "" then
                goto continue
            end

            local embed = nil
            if evt.kind == "player.rank_changed" then
                embed = build_rank_embed(evt.data)
            elseif evt.kind == "player.match_new" then
                embed = build_match_embed(evt.data)
            elseif evt.kind == "player.game_started" then
                embed = build_game_embed(evt.data)
            elseif evt.kind == "player.goal_achieved" then
                embed = build_goal_embed(evt.data)
            end

            if embed then
                local url_str = tostring(effective_url)
                local ok, payload = send_webhook(url_str, embed)
                if not ok and storage then
                    storage:enqueue_notification({webhook_url = url_str, payload = payload})
                end
            end

            ::continue::
        end
    end
end

return {main = main}
