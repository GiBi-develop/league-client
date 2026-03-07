local http = require("http")
local json = require("json")
local contract = require("contract")

--- Generate a daily tip based on recent performance.
local function compute_tip(avg_stats, today)
    if not avg_stats then return "Play some games to get personalized tips!" end
    local avg_d = tonumber(avg_stats.avg_d) or 0
    local avg_cs = tonumber(avg_stats.avg_cs_min) or 0
    local avg_vision = tonumber(avg_stats.avg_vision) or 0
    local avg_wr = tonumber(avg_stats.avg_wr) or 0
    local avg_k = tonumber(avg_stats.avg_k) or 0
    local avg_a = tonumber(avg_stats.avg_a) or 0

    if avg_d > 7 then
        return "You're dying too often — try to play more cautiously and respect enemy power spikes."
    elseif avg_cs < 5 then
        return "Your CS is low — focus on last-hitting minions and aim for 7+ CS per minute."
    elseif avg_vision < 15 then
        return "Ward more! Vision control wins games — buy Control Wards every back."
    elseif avg_wr < 45 then
        return "Your win rate is below 50% — consider narrowing your champion pool to 2-3 picks."
    elseif avg_d > 5 then
        return "Reduce your deaths — play around your cooldowns and avoid fighting when abilities are down."
    elseif avg_cs < 7 then
        return "Aim for 8+ CS/min — spend time in practice tool working on your wave management."
    elseif avg_k + avg_a > 0 and avg_d > 0 then
        local kda = (avg_k + avg_a) / avg_d
        if kda > 4 then
            return "Excellent KDA! You're playing very clean. Focus on converting leads into objectives."
        end
    end
    return "Solid performance! Keep focusing on objectives and team coordination."
end

--- Compute form trend: WR delta last 7 days vs prior 7 days.
local function compute_form_trend(wr_history)
    if not wr_history or #wr_history == 0 then return nil end

    -- wr_history entries have: date, wins, losses, games, winrate
    local recent_wins = 0
    local recent_games = 0
    local prior_wins = 0
    local prior_games = 0

    -- Sort by date desc (most recent first) — already ordered from DB
    for i, day in ipairs(wr_history) do
        if i <= 7 then
            recent_wins = recent_wins + (day.wins or 0)
            recent_games = recent_games + (day.games or 0)
        elseif i <= 14 then
            prior_wins = prior_wins + (day.wins or 0)
            prior_games = prior_games + (day.games or 0)
        end
    end

    local recent_wr = recent_games > 0 and (recent_wins / recent_games * 100) or nil
    local prior_wr = prior_games > 0 and (prior_wins / prior_games * 100) or nil

    if not recent_wr then return nil end

    local delta = nil
    if prior_wr then
        delta = recent_wr - prior_wr
    end

    return {
        recent_wr = math.floor(recent_wr + 0.5),
        recent_games = recent_games,
        prior_wr = prior_wr and math.floor(prior_wr + 0.5) or nil,
        prior_games = prior_games,
        delta = delta and math.floor(delta + 0.5) or nil,
    }
end

--- GET /api/player/{puuid}/stats — Duo partners, WR history, LP history, today stats, peak LP
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

    -- Today stats (#1)
    local today = storage:get_today_stats({puuid = puuid})

    -- Peak LP (#2)
    local peak_lp = storage:get_peak_lp({puuid = puuid}) or {}

    -- Recent avg stats (for daily tip)
    local avg_stats = storage:get_recent_avg_stats({puuid = puuid, limit = 20})

    -- Form trend (#3)
    local form_trend = compute_form_trend(wr_history)

    -- Daily tip (#9)
    local tip = compute_tip(avg_stats, today)

    res:set_status(200)
    res:write_json({
        duo_partners = duo_partners,
        wr_history = wr_history,
        lp_history = {
            solo = lp_history_solo,
            flex = lp_history_flex,
        },
        today = today,
        peak_lp = peak_lp,
        form_trend = form_trend,
        tip = tip,
    })
end

return {handler = handler}
