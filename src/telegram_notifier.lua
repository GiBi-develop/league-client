local logger = require("logger")
local events = require("events")
local env = require("env")
local http_client = require("http_client")
local json = require("json")

--- Format rank change message.
local function fmt_rank_changed(data)
    local old = (data.old_tier or "") .. " " .. (data.old_rank or "") .. " " .. tostring(data.old_lp or 0) .. "LP"
    local new = (data.new_tier or "") .. " " .. (data.new_rank or "") .. " " .. tostring(data.new_lp or 0) .. "LP"
    local lp_diff = (data.new_lp or 0) - (data.old_lp or 0)
    local diff_str = lp_diff >= 0 and ("+" .. lp_diff) or tostring(lp_diff)
    return "📊 *" .. (data.player_name or "?") .. "* — Rank Update\n"
        .. old .. " → " .. new .. " (" .. diff_str .. " LP)"
end

--- Format match result message.
local function fmt_match(data)
    local result = data.win and "✅ Victory" or "❌ Defeat"
    local kda = tostring(data.kills or 0) .. "/" .. tostring(data.deaths or 0) .. "/" .. tostring(data.assists or 0)
    local champ = data.champion_name or "Unknown"
    local lp_str = ""
    if data.lp_diff then
        lp_str = data.lp_diff >= 0 and (" +" .. data.lp_diff .. " LP") or (" " .. data.lp_diff .. " LP")
    end
    return result .. lp_str .. "\n*" .. (data.player_name or "?") .. "* — " .. champ .. " " .. kda
end

--- Format game started message.
local function fmt_game_started(data)
    local mode = data.queue_id and tostring(data.queue_id) or (data.game_mode or "Game")
    return "🎮 *" .. (data.player_name or "?") .. "* entered a game (" .. mode .. ")"
end

--- Format goal achieved message.
local function fmt_goal_achieved(data)
    return "🏆 *" .. (data.player_name or "?") .. "* achieved goal: " .. (data.target_value or "?")
end

--- Send a message via Telegram Bot API.
local function send_telegram(bot_token, chat_id, text)
    local url = "https://api.telegram.org/bot" .. bot_token .. "/sendMessage"
    local payload = json.encode({
        chat_id = chat_id,
        text = text,
        parse_mode = "Markdown",
    })

    local resp, err = http_client.post(url, {
        headers = {["Content-Type"] = "application/json"},
        body = payload,
        timeout = "10s",
    })

    if err then
        logger:error("Telegram send failed", {error = tostring(err)})
        return false
    end

    if resp.status_code ~= 200 then
        logger:error("Telegram API error", {status = resp.status_code, body = resp.body})
        return false
    end

    logger:debug("Telegram notification sent")
    return true
end

--- Telegram Notifier main loop.
local function main()
    logger:info("Telegram notifier started", {pid = process.pid()})

    local bot_token = env.get("TELEGRAM_BOT_TOKEN")
    local chat_id = env.get("TELEGRAM_CHAT_ID")

    if not bot_token or bot_token == "" or not chat_id or chat_id == "" then
        logger:warn("TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set, notifier will idle")
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
                logger:info("Telegram notifier stopping")
                return 0
            end
        else
            local evt = r.value

            -- Re-read env each loop to support hot config changes
            bot_token = env.get("TELEGRAM_BOT_TOKEN")
            chat_id = env.get("TELEGRAM_CHAT_ID")

            if not bot_token or bot_token == "" or not chat_id or chat_id == "" then
                goto continue
            end

            if not evt.data.discord_notify then
                goto continue
            end

            local text = nil
            if evt.kind == "player.rank_changed" then
                text = fmt_rank_changed(evt.data)
            elseif evt.kind == "player.match_new" then
                text = fmt_match(evt.data)
            elseif evt.kind == "player.game_started" then
                text = fmt_game_started(evt.data)
            elseif evt.kind == "player.goal_achieved" then
                text = fmt_goal_achieved(evt.data)
            end

            if text then
                send_telegram(bot_token, chat_id, text)
            end

            ::continue::
        end
    end
end

return {main = main}
