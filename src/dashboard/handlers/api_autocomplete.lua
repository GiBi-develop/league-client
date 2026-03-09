local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/autocomplete?q=... — Search cached players by name.
local function handler()
    local res = http.response()
    local req = http.request()

    local q = req:query("q")
    if not q or q == "" then
        res:set_status(200)
        res:write_json({})
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(200)
        res:write_json({})
        return
    end

    local results = storage:search_players({query = q, limit = 8}) or {}
    res:set_status(200)
    res:write_json(results)
end

return {handler = handler}
