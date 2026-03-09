local http = require("http")
local json = require("json")
local funcs = require("funcs")
local env = require("env")
local contract = require("contract")

--- GET /api/multi-search?players=Name1%23Tag1,Name2%23Tag2&platform=RU
--- Returns brief profiles for multiple players (lobby tool).
local function handler()
    local res = http.response()
    local req = http.request()

    local players_str = req:query("players")
    local platform = req:query("platform") or env.get("RIOT_PLATFORM") or "EUW1"

    if not players_str or players_str == "" then
        res:set_status(400)
        res:write_json({error = "players parameter required (comma-separated Name#Tag)"})
        return
    end

    -- Map platform to region
    local region = env.get("RIOT_REGION") or "EUROPE"
    local upper_platform = string.upper(platform)
    if upper_platform == "NA1" or upper_platform == "BR1" or upper_platform == "LA1" or upper_platform == "LA2" or upper_platform == "OC1" then
        region = "AMERICAS"
    elseif upper_platform == "KR" or upper_platform == "JP1" then
        region = "ASIA"
    elseif upper_platform == "PH2" or upper_platform == "SG2" or upper_platform == "TH2" or upper_platform == "TW2" or upper_platform == "VN2" then
        region = "SEA"
    end

    local storage, serr = contract.open("app.lc.lib:player_storage")

    -- Parse player list (max 10)
    local player_list = {}
    for entry in string.gmatch(players_str, "[^,]+") do
        local trimmed = entry:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(player_list, trimmed)
        end
        if #player_list >= 10 then break end
    end

    -- Launch parallel account lookups
    local async_handles = {}
    for i, player_str in ipairs(player_list) do
        -- Split by # to get name and tag
        local name, tag = player_str:match("^(.+)#(.+)$")
        if name and tag then
            local handle, _ = funcs.async("app.lc:riot_api_get_account", {
                game_name = name,
                tag_line = tag,
                region = region,
            })
            async_handles[i] = {handle = handle, name = name, tag = tag}
        else
            async_handles[i] = {handle = nil, name = player_str, tag = "", error = "invalid format"}
        end
    end

    -- Collect account results and launch ranked lookups
    local ranked_handles = {}
    local accounts = {}
    for i, entry in ipairs(async_handles) do
        if entry.error then
            accounts[i] = {name = entry.name, tag = entry.tag, error = entry.error}
        elseif entry.handle then
            local payload, ok = entry.handle:channel():receive()
            if ok and payload then
                local account = payload:data()
                if account and account.puuid then
                    accounts[i] = {
                        puuid = account.puuid,
                        name = account.gameName or entry.name,
                        tag = account.tagLine or entry.tag,
                    }
                    -- Launch ranked lookup
                    local rh, _ = funcs.async("app.lc:riot_api_get_ranked", {
                        puuid = account.puuid,
                        platform = platform,
                    })
                    ranked_handles[i] = rh
                else
                    accounts[i] = {name = entry.name, tag = entry.tag, error = "not found"}
                end
            else
                accounts[i] = {name = entry.name, tag = entry.tag, error = "lookup failed"}
            end
        end
    end

    -- Collect ranked results and build response
    local results = {}
    for i, acct in ipairs(accounts) do
        if acct.error then
            table.insert(results, {
                name = acct.name,
                tag = acct.tag,
                error = acct.error,
            })
        else
            local ranked = {}
            if ranked_handles[i] then
                local payload, ok = ranked_handles[i]:channel():receive()
                if ok and payload then ranked = payload:data() or {} end
            end

            -- Find Solo/Duo rank
            local solo_tier, solo_rank, solo_lp, solo_wr = nil, nil, nil, nil
            for _, r in ipairs(ranked) do
                if r.queueType == "RANKED_SOLO_5x5" then
                    solo_tier = r.tier
                    solo_rank = r.rank
                    solo_lp = r.leaguePoints
                    local total = (r.wins or 0) + (r.losses or 0)
                    solo_wr = total > 0 and math.floor((r.wins or 0) / total * 100 + 0.5) or nil
                    break
                end
            end

            -- Get recent stats from cache if available
            local recent_wr, recent_games, streak, main_champions = nil, nil, nil, {}
            if not serr and storage then
                local matches = storage:get_matches({puuid = acct.puuid, limit = 20})
                if matches and #matches > 0 then
                    local wins = 0
                    local cur_streak = 0
                    local streak_type = ""
                    local champ_games = {}
                    for mi, m in ipairs(matches) do
                        if m.win == 1 then wins = wins + 1 end
                        -- Streak
                        if mi == 1 then
                            streak_type = m.win == 1 and "W" or "L"
                            cur_streak = 1
                        elseif (m.win == 1 and streak_type == "W") or (m.win ~= 1 and streak_type == "L") then
                            cur_streak = cur_streak + 1
                        end
                        -- Champion count
                        local cn = m.champion_name or "Unknown"
                        champ_games[cn] = (champ_games[cn] or 0) + 1
                    end
                    recent_games = #matches
                    recent_wr = math.floor(wins / #matches * 100 + 0.5)
                    streak = (streak_type == "W" and cur_streak or -cur_streak)

                    -- Top 3 champions
                    local champ_list = {}
                    for cn, count in pairs(champ_games) do
                        table.insert(champ_list, {name = cn, games = count})
                    end
                    table.sort(champ_list, function(a, b) return a.games > b.games end)
                    for ci = 1, math.min(3, #champ_list) do
                        table.insert(main_champions, champ_list[ci].name)
                    end
                end
            end

            table.insert(results, {
                puuid = acct.puuid,
                name = acct.name,
                tag = acct.tag,
                tier = solo_tier,
                rank = solo_rank,
                lp = solo_lp,
                winrate = solo_wr,
                recent_wr = recent_wr,
                recent_games = recent_games,
                streak = streak,
                main_champions = main_champions,
            })
        end
    end

    res:set_status(200)
    res:write_json({players = results})
end

return {handler = handler}
