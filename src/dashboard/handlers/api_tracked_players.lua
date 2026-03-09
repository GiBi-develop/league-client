local http = require("http")
local contract = require("contract")

--- GET /api/tracked-players — returns all tracked players with current ranked + today stats
local function handler()
    local res = http.response()

    local storage, serr = contract.open("app.lc.lib:player_storage")
    if serr then
        res:set_status(500)
        res:set_content_type("text/plain")
        res:write("storage error")
        return
    end

    local players = storage:list_tracked_players()
    if not players or type(players) ~= "table" then
        res:write_json({players = {}})
        return
    end

    local result = {}
    for _, p in ipairs(players) do
        local puuid = tostring(p.puuid or "")
        if puuid ~= "" then
            local ranked_rows = storage:get_ranked({puuid = puuid})
            local today = storage:get_today_stats({puuid = puuid})

            -- Find Solo/Duo and Flex ranked entries
            local solo = nil
            local flex = nil
            if ranked_rows and type(ranked_rows) == "table" then
                for _, r in ipairs(ranked_rows) do
                    local qt = tostring(r.queue_type)
                    if qt == "RANKED_SOLO_5x5" then solo = r
                    elseif qt == "RANKED_FLEX_SR" then flex = r
                    end
                end
            end

            local function ranked_entry(r)
                if not r then return nil end
                local wins = tonumber(r.wins) or 0
                local losses = tonumber(r.losses) or 0
                local total = wins + losses
                return {
                    tier = tostring(r.tier or ""),
                    rank = tostring(r.rank or ""),
                    lp = tonumber(r.league_points) or 0,
                    wins = wins,
                    losses = losses,
                    wr = total > 0 and math.floor(100 * wins / total + 0.5) or 0,
                    hot_streak = (tonumber(r.hot_streak) or 0) == 1,
                }
            end

            local today_stats = nil
            if today then
                local tg = tonumber(today.games) or 0
                local tw = tonumber(today.wins) or 0
                today_stats = {
                    games = tg,
                    wins = tw,
                    losses = tg - tw,
                }
            end

            table.insert(result, {
                puuid = puuid,
                game_name = tostring(p.game_name or ""),
                tag_line = tostring(p.tag_line or ""),
                summoner_level = tonumber(p.summoner_level) or 0,
                profile_icon_id = tonumber(p.profile_icon_id) or 0,
                platform = tostring(p.platform or "EUW1"),
                match_count = tonumber(p.match_count) or 0,
                updated_at = tostring(p.updated_at or ""),
                solo = ranked_entry(solo),
                flex = ranked_entry(flex),
                today = today_stats,
            })
        end
    end

    res:write_json({players = result})
end

return {handler = handler}
