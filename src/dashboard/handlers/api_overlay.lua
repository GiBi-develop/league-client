local http = require("http")
local contract = require("contract")

--- GET /overlay/{puuid} — OBS Browser Source overlay (200×320px transparent widget)
local function handler()
    local res = http.response()
    local req = http.request()
    local puuid = req:param("puuid")

    if not puuid or puuid == "" then
        res:set_status(400)
        res:set_content_type("text/plain")
        res:write("puuid required")
        return
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:set_content_type("text/plain")
        res:write("storage error")
        return
    end

    local player = storage:get_player({puuid = puuid})
    local ranked_rows = storage:get_ranked({puuid = puuid})
    local today = storage:get_today_stats({puuid = puuid})
    local recent = storage:get_matches({puuid = puuid, limit = 5})

    -- Find Solo/Duo ranked entry
    local solo = nil
    if ranked_rows and type(ranked_rows) == "table" then
        for _, r in ipairs(ranked_rows) do
            if tostring(r.queue_type) == "RANKED_SOLO_5x5" then solo = r; break end
        end
    end

    local name = player and tostring(player.game_name or "Player") or "Player"
    local rank_str = "Unranked"
    if solo then
        rank_str = tostring(solo.tier or "") .. " " .. tostring(solo.rank or "") .. " " .. tostring(solo.league_points or 0) .. " LP"
    end

    local today_games = today and (tonumber(today.games) or 0) or 0
    local today_wins = today and (tonumber(today.wins) or 0) or 0
    local today_str = today_games > 0 and (tostring(today_wins) .. "W " .. tostring(today_games - today_wins) .. "L today") or "No games today"

    -- Build W/L dots HTML
    local dots_html = ""
    if recent and type(recent) == "table" then
        for _, m in ipairs(recent) do
            local cls = (tonumber(m.win) or 0) == 1 and "W" or "L"
            dots_html = dots_html .. '<div class="wl-dot ' .. cls .. '">' .. cls .. '</div>'
        end
    end

    local html = [[<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="60">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:transparent;font-family:system-ui,sans-serif;width:220px;padding:10px}
.card{background:rgba(10,15,30,0.88);border:1px solid rgba(200,155,60,0.45);border-radius:8px;padding:12px 14px;color:#e2e8f0}
.name{font-size:14px;font-weight:700;color:#c89b3c;margin-bottom:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rank{font-size:12px;color:#94a3b8;margin-bottom:5px}
.today{font-size:12px;color:#22c55e;margin-bottom:7px}
.wl{display:flex;gap:4px}
.wl-dot{width:18px;height:18px;border-radius:3px;font-size:9px;font-weight:700;display:flex;align-items:center;justify-content:center}
.wl-dot.W{background:rgba(34,197,94,0.25);color:#22c55e}
.wl-dot.L{background:rgba(239,68,68,0.25);color:#ef4444}
</style></head>
<body><div class="card">
<div class="name">]] .. name .. [[</div>
<div class="rank">]] .. rank_str .. [[</div>
<div class="today">]] .. today_str .. [[</div>
<div class="wl">]] .. dots_html .. [[</div>
</div></body></html>]]

    res:set_status(200)
    res:set_content_type("text/html; charset=utf-8")
    res:write(html)
end

return {handler = handler}
