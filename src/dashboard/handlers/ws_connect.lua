local http = require("http")
local json = require("json")

--- WS upgrade handler — spawns a dashboard session process
--- and tells the relay middleware to target it.
local function handler()
    local res = http.response()
    local pid = process.spawn("app.lc.dashboard:session_process", "app.lc:processes")

    res:set_header("X-WS-Relay", json.encode({
        target_pid = tostring(pid),
        message_topic = "ws.message",
        heartbeat_interval = "30s",
    }))
end

return { handler = handler }
