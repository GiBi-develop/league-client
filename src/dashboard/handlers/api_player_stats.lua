local http = require("http")
local json = require("json")
local contract = require("contract")

--- Compute LP velocity (LP per day trend) from ranked history.
local function compute_lp_velocity(lp_history)
    if not lp_history or #lp_history < 3 then return nil end

    local function tier_base(t)
        if t == "IRON" then return 0
        elseif t == "BRONZE" then return 400
        elseif t == "SILVER" then return 800
        elseif t == "GOLD" then return 1200
        elseif t == "PLATINUM" then return 1600
        elseif t == "EMERALD" then return 2000
        elseif t == "DIAMOND" then return 2400
        else return 2800 end
    end

    local function rank_base(r)
        if r == "IV" then return 0
        elseif r == "III" then return 100
        elseif r == "II" then return 200
        elseif r == "I" then return 300
        else return 0 end
    end

    local function to_abs(entry)
        return tier_base(tostring(entry.tier or ""))
            + rank_base(tostring(entry.rank or ""))
            + (tonumber(entry.league_points) or 0)
    end

    local newest = lp_history[1]
    local oldest = lp_history[#lp_history]
    local newest_abs = to_abs(newest)
    local oldest_abs = to_abs(oldest)
    local lp_diff = newest_abs - oldest_abs
    -- Approximate: treat entry count / 2 as days sampled
    local days = math.max(1, math.floor(#lp_history / 2))
    local lp_per_day = lp_diff / days

    local next_div = math.ceil((newest_abs + 1) / 100) * 100
    local days_to_next = lp_per_day > 0 and math.ceil((next_div - newest_abs) / lp_per_day) or nil

    local trend = "stable"
    if lp_per_day > 5 then trend = "climbing"
    elseif lp_per_day < -5 then trend = "falling" end

    return {
        lp_per_day = math.floor(lp_per_day + 0.5),
        lp_diff = lp_diff,
        days_to_next_div = days_to_next,
        trend = trend,
    }
end

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

--- Compute playstyle archetype from aggregated stats.
local function compute_playstyle(avg_stats, damage_profile, role_dist, vision_trend)
    if not avg_stats then return nil end

    local avg_k = tonumber(avg_stats.avg_k) or 0
    local avg_d = tonumber(avg_stats.avg_d) or 0
    local avg_a = tonumber(avg_stats.avg_a) or 0
    local avg_cs = tonumber(avg_stats.avg_cs_min) or 0
    local avg_vis = tonumber(avg_stats.avg_vision) or 0
    local avg_wr = tonumber(avg_stats.avg_wr) or 50
    local kda = avg_d > 0 and ((avg_k + avg_a) / avg_d) or (avg_k + avg_a)

    -- Check damage type dominance
    local magic_pct = 0
    local phys_pct = 0
    if damage_profile and damage_profile.avg_magic_pct then
        magic_pct = tonumber(damage_profile.avg_magic_pct) or 0
        phys_pct = tonumber(damage_profile.avg_physical_pct) or 0
    end

    -- Find main role
    local main_role = nil
    local main_role_games = 0
    if role_dist then
        for _, r in ipairs(role_dist) do
            local g = tonumber(r.games) or 0
            if g > main_role_games then
                main_role_games = g
                main_role = r.position
            end
        end
    end

    -- Avg vision per min from trend
    local avg_vpm = 0
    if vision_trend and #vision_trend > 0 then
        local total = 0
        for _, v in ipairs(vision_trend) do total = total + (tonumber(v.vision_per_min) or 0) end
        avg_vpm = total / #vision_trend
    end

    -- Determine archetype
    if avg_vpm >= 1.5 and avg_vis >= 30 then
        return {archetype = "Vision Master", icon = "eye", description = "Exceptional ward control and map awareness"}
    elseif avg_k >= 8 and avg_d <= 4 then
        return {archetype = "Aggressive Carry", icon = "sword", description = "High kill threat with clean play"}
    elseif avg_cs >= 8 and avg_k < 5 then
        return {archetype = "Farm Machine", icon = "wheat", description = "Prioritizes CS and scaling over fights"}
    elseif avg_a >= 12 and avg_k < 4 then
        return {archetype = "Team Player", icon = "shield", description = "Enables teammates over carrying solo"}
    elseif kda >= 4 and avg_d <= 3 then
        return {archetype = "Safe Player", icon = "anchor", description = "Rarely dies, consistent and reliable"}
    elseif avg_k >= 6 and avg_d >= 7 then
        return {archetype = "Coinflip", icon = "dice", description = "High risk, high reward playstyle"}
    elseif main_role == "JUNGLE" and avg_a >= 8 then
        return {archetype = "Ganker", icon = "target", description = "Focuses on creating advantages through ganks"}
    elseif main_role == "UTILITY" then
        return {archetype = "Support Main", icon = "heart", description = "Dedicated to enabling the team"}
    elseif avg_cs >= 7 and kda >= 3 then
        return {archetype = "Well-Rounded", icon = "star", description = "Balanced mix of farming and fighting"}
    else
        return {archetype = "Versatile", icon = "refresh", description = "Adapts to the game state"}
    end
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

    -- LP Velocity (#new)
    local lp_velocity = compute_lp_velocity(lp_history_solo)

    -- Personal Enemies (#new)
    local personal_enemies = storage:get_personal_enemies({puuid = puuid, min_games = 3, limit = 5}) or {}

    -- Personal Records (#11)
    local records_result = storage:get_records({puuid = puuid})
    local records = records_result and records_result.records or {}

    -- Season History (#6)
    local season_history = storage:get_season_history({puuid = puuid}) or {}

    -- Wave 4: Role distribution
    local role_distribution = storage:get_role_distribution({puuid = puuid}) or {}

    -- Wave 4: Damage composition profile
    local damage_profile = storage:get_damage_profile({puuid = puuid, limit = 50}) or {}

    -- Wave 4: Game duration win rate buckets
    local duration_analysis = storage:get_duration_analysis({puuid = puuid}) or {}

    -- Wave 4: Win rate by time of day / day of week
    local time_analysis = storage:get_time_analysis({puuid = puuid}) or {}

    -- Wave 4: Surrender, remake, first blood stats
    local surrender_stats = storage:get_surrender_stats({puuid = puuid}) or {}

    -- Wave 4: Multi-queue breakdown
    local queue_breakdown = storage:get_queue_breakdown({puuid = puuid}) or {}

    -- Wave 4: Summoner spell analysis
    local spell_analysis = storage:get_spell_analysis({puuid = puuid}) or {}

    -- Wave 5: Vision trend
    local vision_trend = storage:get_vision_trend({puuid = puuid, limit = 20}) or {}

    -- Wave 5: Peer percentiles
    local peer_percentiles = storage:get_peer_percentiles({puuid = puuid}) or {}

    -- Wave 5: Early game stats (from timeline data)
    local early_game = storage:get_early_game_stats({puuid = puuid, limit = 20}) or {}

    -- Wave 6: Objective control stats
    local objective_stats = storage:get_objective_stats({puuid = puuid}) or {}

    -- Quick Win: Tilt score
    local tilt_score = storage:get_tilt_score({puuid = puuid}) or {}

    -- Quick Win: Playstyle clustering
    local playstyle = compute_playstyle(avg_stats, damage_profile, role_distribution, vision_trend)

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
        lp_velocity = lp_velocity,
        personal_enemies = personal_enemies,
        records = records,
        season_history = season_history,
        role_distribution = role_distribution,
        damage_profile = damage_profile,
        duration_analysis = duration_analysis,
        time_analysis = time_analysis,
        surrender_stats = surrender_stats,
        queue_breakdown = queue_breakdown,
        spell_analysis = spell_analysis,
        vision_trend = vision_trend,
        peer_percentiles = peer_percentiles,
        early_game = early_game,
        objective_stats = objective_stats,
        tilt_score = tilt_score,
        playstyle = playstyle,
    })
end

return {handler = handler}
