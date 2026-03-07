local http = require("http")
local contract = require("contract")

--- GET /health — Healthcheck endpoint (#17).
local function handler()
    local res = http.response()

    -- Check DB connectivity
    local db_ok = true
    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        db_ok = false
    else
        local result = storage:get_player({puuid = "healthcheck"})
        _ = result
    end

    if db_ok then
        res:set_status(200)
        res:write_json({status = "ok", db = "ok"})
    else
        res:set_status(503)
        res:write_json({status = "degraded", db = "error"})
    end
end

return {handler = handler}
