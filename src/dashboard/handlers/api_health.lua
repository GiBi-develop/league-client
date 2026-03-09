local http = require("http")
local contract = require("contract")

--- GET /health — Extended healthcheck with API metrics and data freshness.
local function handler()
    local res = http.response()

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(503)
        res:write_json({status = "degraded", db = "error", error = tostring(serr)})
        return
    end

    -- Check DB connectivity
    local db_ok = true
    local result = storage:get_player({puuid = "healthcheck"})
    _ = result

    -- API metrics summary (last hour)
    local api_metrics = storage:get_api_metrics_summary({}) or {}

    -- Player data freshness
    local freshness = storage:get_player_freshness({}) or {}

    -- Check for stale players (>30 min without update)
    local stale_players = {}
    for _, p in ipairs(freshness) do
        if (tonumber(p.minutes_ago) or 0) > 30 then
            table.insert(stale_players, {
                name = (p.game_name or "") .. "#" .. (p.tag_line or ""),
                minutes_ago = p.minutes_ago,
            })
        end
    end

    local has_alerts = #stale_players > 0 or (tonumber(api_metrics.rate_limited) or 0) > 0

    res:set_status(db_ok and 200 or 503)
    res:write_json({
        status = has_alerts and "warning" or "ok",
        db = db_ok and "ok" or "error",
        api = {
            total_calls_1h = tonumber(api_metrics.total_calls) or 0,
            success = tonumber(api_metrics.success) or 0,
            errors = tonumber(api_metrics.errors) or 0,
            rate_limited = tonumber(api_metrics.rate_limited) or 0,
            cache_hits = tonumber(api_metrics.cache_hits) or 0,
            avg_response_ms = tonumber(api_metrics.avg_response_ms) or 0,
        },
        players = freshness,
        alerts = stale_players,
    })
end

return {handler = handler}
