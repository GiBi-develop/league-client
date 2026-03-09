local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/match/{matchId}/recap — Template-based match recap (#23).
local function handler()
    local res = http.response()
    local req = http.request()

    local match_id = req:param("matchId")
    local puuid = req:query("puuid")
    if not match_id or match_id == "" or not puuid or puuid == "" then
        res:set_status(400)
        res:write_json({error = "matchId and puuid are required"})
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:write_json({error = "storage unavailable"})
        return
    end

    local result = storage:get_match_recap({match_id = match_id, puuid = puuid})

    res:set_status(200)
    res:write_json(result)
end

return {handler = handler}
