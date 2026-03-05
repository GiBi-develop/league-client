local http = require("http")
local json = require("json")
local contract = require("contract")

--- GET /api/player/{puuid}/stats — Duo partners, WR history, LP history
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

    -- Duo partners
    local duo_partners = storage:get_duo_partners({puuid = puuid, limit = 10}) or {}

    -- Win rate history (last 30 days)
    local wr_history = storage:get_winrate_history({puuid = puuid, days = 30}) or {}

    -- LP history (Solo/Duo)
    local lp_history_solo = storage:get_ranked_history({
        puuid = puuid,
        queue_type = "RANKED_SOLO_5x5",
        limit = 50,
    }) or {}

    -- LP history (Flex)
    local lp_history_flex = storage:get_ranked_history({
        puuid = puuid,
        queue_type = "RANKED_FLEX_SR",
        limit = 50,
    }) or {}

    res:set_status(200)
    res:write_json({
        duo_partners = duo_partners,
        wr_history = wr_history,
        lp_history = {
            solo = lp_history_solo,
            flex = lp_history_flex,
        },
    })
end

return {handler = handler}
