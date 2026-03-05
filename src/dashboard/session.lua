local json = require("json")
local logger = require("logger")
local time = require("time")
local events_mod = require("events")
local contract_mod = require("contract")

local log = logger:named("dashboard.session")

local REFRESH_INTERVAL = "30s"

--- Send a JSON message to the connected WebSocket client.
local function send_to_client(state, message)
    if not state.client_pid then return end
    process.send(state.client_pid, "ws.send", {
        type = "text",
        data = json.encode(message),
    })
end

--- Fetch all tracked players from the DB and build a snapshot.
local function build_snapshot(storage)
    local rows, err = storage:list_tracked_players({})
    if err then
        log:warn("Failed to list tracked players", { error = tostring(err) })
        return nil
    end
    return {
        type = "snapshot",
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        players = rows or {},
    }
end

--- Handle WebSocket join.
local function handle_join(state, data, storage)
    state.client_pid = data.client_pid
    log:info("Dashboard client connected", { client_pid = data.client_pid })

    send_to_client(state, {
        type = "system",
        message = "Connected to League Client Dashboard",
    })

    local snapshot = build_snapshot(storage)
    if snapshot then
        send_to_client(state, snapshot)
    end
end

--- Handle incoming WebSocket messages.
local function handle_ws_message(state, data, storage)
    local raw = data.data
    local ok, msg = pcall(json.decode, raw)
    if not ok or not msg then return end

    if msg.type == "request_snapshot" then
        local snapshot = build_snapshot(storage)
        if snapshot then
            send_to_client(state, snapshot)
        end
    end
end

--- Handle WebSocket leave.
local function handle_leave(state, data)
    log:info("Dashboard client disconnected", { client_pid = data.client_pid })
end

--- Main process loop.
local function main()
    local storage, err = contract_mod.open("app.lc.lib:player_storage")
    if err then
        log:error("Failed to open player_storage contract", { error = tostring(err) })
        return 1
    end

    local state = { client_pid = nil }

    local inbox = process.inbox()
    local proc_events = process.events()
    local refresh_timer = time.after(REFRESH_INTERVAL)

    -- Subscribe to league_client events for live updates
    local lc_sub, sub_err = events_mod.subscribe("league_client")
    if sub_err then
        log:error("Failed to subscribe to league_client events", { error = tostring(sub_err) })
        return 1
    end
    local lc_ch = lc_sub:channel()

    log:info("Dashboard session started", { pid = process.pid() })

    while true do
        local r = channel.select {
            proc_events:case_receive(),
            inbox:case_receive(),
            refresh_timer:case_receive(),
            lc_ch:case_receive(),
        }

        if r.channel == proc_events then
            if r.value.kind == process.event.CANCEL then
                lc_sub:close()
                log:info("Dashboard session shutting down")
                return 0
            end

        elseif r.channel == refresh_timer then
            local snapshot = build_snapshot(storage)
            if snapshot then
                send_to_client(state, snapshot)
            end
            refresh_timer = time.after(REFRESH_INTERVAL)

        elseif r.channel == lc_ch then
            local evt = r.value
            local data = evt.data or {}
            local kind = evt.kind

            if kind == "player.data_fetched" then
                send_to_client(state, {
                    type = "player_update",
                    event = kind,
                    player_id = data.player_id,
                    player_name = data.player_name,
                    puuid = data.puuid,
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                })
            elseif kind == "player.rank_changed" then
                send_to_client(state, {
                    type = "rank_change",
                    event = kind,
                    player_name = data.player_name,
                    queue_type = data.queue_type,
                    old_rank = data.old_tier .. " " .. data.old_rank .. " " .. tostring(data.old_lp) .. "LP",
                    new_rank = data.new_tier .. " " .. data.new_rank .. " " .. tostring(data.new_lp) .. "LP",
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                })
            elseif kind == "player.match_new" then
                send_to_client(state, {
                    type = "new_match",
                    event = kind,
                    player_name = data.player_name,
                    champion_name = data.champion_name,
                    kills = data.kills,
                    deaths = data.deaths,
                    assists = data.assists,
                    win = data.win,
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                })
            elseif kind == "fetch.failed" then
                send_to_client(state, {
                    type = "fetch_failed",
                    player_name = data.player_name,
                    error = data.error,
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                })
            end

        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()
            local payload = msg:payload():data()

            if topic == "ws.join" then
                handle_join(state, payload, storage)
            elseif topic == "ws.message" then
                handle_ws_message(state, payload, storage)
            elseif topic == "ws.leave" then
                handle_leave(state, payload)
                lc_sub:close()
                return 0
            end
        end
    end
end

return { main = main }
