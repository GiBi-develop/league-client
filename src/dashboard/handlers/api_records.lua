local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/player/{puuid}/records — Personal records board (#11).
local function handler()
    local res = http.response()
    local req = http.request()

    local puuid = req:param("puuid")
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

    local result = storage:get_records({puuid = puuid})

    res:set_status(200)
    res:write_json(result)
end

return {handler = handler}
