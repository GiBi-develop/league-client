local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET/POST/DELETE /api/admin/players — Managed tracked players (#18).
local function handler()
    local res = http.response()
    local req = http.request()

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local method = req:method()

    if method == "GET" then
        local players = storage:list_managed_players()
        res:set_status(200)
        res:write_json({players = players or {}})
        return
    end

    if method == "POST" then
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

        if not data.game_name or not data.tag_line then
            res:set_status(400)
            res:write_json({error = "game_name and tag_line are required"})
            return
        end

        local result = storage:add_managed_player(data)
        if result and result.error then
            res:set_status(500)
            res:write_json({error = result.error})
            return
        end

        res:set_status(201)
        res:write_json(result or {ok = true})
        return
    end

    if method == "DELETE" then
        local id = req:query("id")
        if not id or id == "" then
            res:set_status(400)
            res:write_json({error = "id is required"})
            return
        end

        local result = storage:remove_managed_player({id = tonumber(id)})
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
