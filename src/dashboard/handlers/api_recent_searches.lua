local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/recent-searches
--- Returns recent player searches with ranked data.
local function handler()
    local res = http.response()

    local storage, err = contract.open("app.lc.lib:player_storage")
    if err then
        res:set_status(500)
        res:write_json({error = "Internal error"})
        return
    end

    local searches = storage:get_recent_searches({limit = 10})

    res:set_status(200)
    res:write_json({searches = searches or {}})
end

return {handler = handler}
