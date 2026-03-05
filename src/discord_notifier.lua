local logger = require("logger")
local events = require("events")
local env = require("env")
local http_client = require("http_client")
local json = require("json")

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
    local total = (data.wins or 0) + (data.losses or 0)
    if total > 0 then
        winrate = math.floor(data.wins / total * 100)
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
            {name = "Win Rate", value = tostring(winrate) .. "% (" .. tostring(data.wins or 0) .. "W " .. tostring(data.losses or 0) .. "L)", inline = true},
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

    return {
        title = data.player_name .. " — " .. result .. lp_str,
        color = color,
        fields = fields,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

--- Send an embed to Discord via webhook.
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
        return
    end

    if resp.status_code ~= 204 and resp.status_code ~= 200 then
        logger:error("Discord webhook returned error", {
            status = resp.status_code,
            body = resp.body,
        })
        return
    end

    logger:debug("Discord notification sent")
end

--- Discord Notifier main loop.
local function main()
    logger:info("Discord notifier started", {pid = process.pid()})

    local webhook_url = env.get("DISCORD_WEBHOOK_URL")
    if not webhook_url or webhook_url == "" then
        logger:warn("DISCORD_WEBHOOK_URL not set, notifier will idle")
    end

    local sub, err = events.subscribe("league_client")
    if err then
        logger:error("Failed to subscribe to events", {error = tostring(err)})
        return 1
    end

    local ch = sub:channel()
    local evts = process.events()

    while true do
        local r = channel.select {
            ch:case_receive(),
            evts:case_receive(),
        }

        if r.channel == evts then
            if r.value.kind == process.event.CANCEL then
                sub:close()
                logger:info("Discord notifier stopping")
                return 0
            end
        else
            local evt = r.value

            webhook_url = env.get("DISCORD_WEBHOOK_URL")
            if not webhook_url or webhook_url == "" then
                goto continue
            end

            -- Only send Discord notifications for players with discord_notify enabled
            if not evt.data.discord_notify then
                goto continue
            end

            if evt.kind == "player.rank_changed" then
                local embed = build_rank_embed(evt.data)
                send_webhook(webhook_url, embed)
            elseif evt.kind == "player.match_new" then
                local embed = build_match_embed(evt.data)
                send_webhook(webhook_url, embed)
            end

            ::continue::
        end
    end
end

return {main = main}
