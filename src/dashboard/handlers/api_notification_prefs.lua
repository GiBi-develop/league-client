local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET/PUT /api/notification-prefs?puuid=... (#13)
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:query("puuid")
    if not puuid or puuid == "" then
        res:set_status(400)
        res:write_json({error = "puuid is required"})
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local method = req:method()

    if method == "GET" then
        local prefs = storage:get_notification_prefs({puuid = puuid})
        res:set_status(200)
        res:write_json(prefs or {})
        return
    end

    if method == "PUT" then
        local body = req:body()
        if not body or body == "" then
            res:set_status(400)
            res:write_json({error = "body is required"})
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or not data then
            res:set_status(400)
            res:write_json({error = "invalid JSON"})
            return
        end

        data.puuid = puuid
        local result = storage:save_notification_prefs(data)
        if result and result.error then
            res:set_status(500)
            res:write_json({error = result.error})
            return
        end

        res:set_status(200)
        res:write_json({ok = true})
        return
    end

    res:set_status(405)
    res:write_json({error = "method not allowed"})
end

return {handler = handler}
