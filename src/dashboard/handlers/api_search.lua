local http = require("http")
local json = require("json")
local funcs = require("funcs")
local env = require("env")
local contract = require("contract")

--- Extract rune/perk info from participant.
local function extract_perks(participant)
    local keystone = 0
    local primary_style = 0
    local sub_style = 0

    if participant.perks and participant.perks.styles then
        for _, style in ipairs(participant.perks.styles) do
            if style.description == "primaryStyle" then
                primary_style = style.style or 0
                if style.selections and #style.selections > 0 then
                    keystone = style.selections[1].perk or 0
                end
            elseif style.description == "subStyle" then
                sub_style = style.style or 0
            end
        end
    end

    return keystone, primary_style, sub_style
end

--- Build full participant data from raw API participant.
local function build_participant_data(p, champions)
    local p_champ = champions[tostring(p.championId)]
    local p_cs = (p.totalMinionsKilled or 0) + (p.neutralMinionsKilled or 0)
    local p_items = {}
    for idx = 0, 6 do
        local item_id = p["item" .. idx]
        if item_id and item_id > 0 then
            table.insert(p_items, item_id)
        end
    end

    local keystone, primary_style, sub_style = extract_perks(p)
    local challenges = p.challenges or {}

    return {
        puuid = p.puuid,
        summoner_name = p.riotIdGameName or p.summonerName or "Unknown",
        tag_line = p.riotIdTagline or "",
        champion_id = p.championId,
        champion_name = p.championName,
        champion_image = p_champ and p_champ.image or nil,
        team_id = p.teamId,
        kills = p.kills or 0,
        deaths = p.deaths or 0,
        assists = p.assists or 0,
        cs = p_cs,
        total_damage = p.totalDamageDealtToChampions or 0,
        gold_earned = p.goldEarned or 0,
        vision_score = p.visionScore or 0,
        position = p.teamPosition or "",
        win = p.win,
        items = p_items,
        summoner1 = p.summoner1Id or 0,
        summoner2 = p.summoner2Id or 0,
        double_kills = p.doubleKills or 0,
        triple_kills = p.tripleKills or 0,
        quadra_kills = p.quadraKills or 0,
        penta_kills = p.pentaKills or 0,
        physical_damage = p.physicalDamageDealtToChampions or 0,
        magic_damage = p.magicDamageDealtToChampions or 0,
        true_damage = p.trueDamageDealtToChampions or 0,
        damage_taken = p.totalDamageTaken or 0,
        wards_placed = p.wardsPlaced or 0,
        wards_killed = p.wardsKilled or 0,
        control_wards = p.detectorWardsPlaced or 0,
        kill_participation = challenges.killParticipation or 0,
        damage_share = challenges.teamDamagePercentage or 0,
        perks_keystone = keystone,
        perks_primary_style = primary_style,
        perks_sub_style = sub_style,
        champ_level = p.champLevel or 0,
    }
end

--- Build match entry from raw API match data for a specific puuid.
local function build_match_entry(mid, match_data, puuid, champions)
    local participant = nil
    if match_data.info and match_data.info.participants then
        for _, p in ipairs(match_data.info.participants) do
            if p.puuid == puuid then
                participant = p
                break
            end
        end
    end
    if not participant then return nil end

    local info = match_data.info  -- keep as any, not {} fallback
    local cs = (participant.totalMinionsKilled or 0) + (participant.neutralMinionsKilled or 0)
    local game_duration = tonumber(info and info.gameDuration) or 0
    local cs_per_min = 0
    if game_duration > 0 then
        cs_per_min = math.floor(cs / (game_duration / 60) * 10) / 10
    end
    local duration_min = math.floor(game_duration / 60)
    local duration_sec = game_duration % 60

    local champ = champions[tostring(participant.championId)]
    local champ_image = champ and champ.image or nil

    local challenges = participant.challenges or {}
    local keystone, primary_style, sub_style = extract_perks(participant)

    -- Build allies and enemies
    local allies = {}
    local enemies = {}
    local my_team = participant.teamId
    local all_participants_raw = {}

    if match_data.info and match_data.info.participants then
        for _, p in ipairs(match_data.info.participants) do
            local player_data = build_participant_data(p, champions)

            table.insert(all_participants_raw, player_data)

            if p.puuid == puuid then
                player_data.is_me = true
            end
            if p.teamId == my_team then
                table.insert(allies, player_data)
            else
                table.insert(enemies, player_data)
            end
        end
    end

    local my_items = {}
    for idx = 0, 6 do
        local item_id = participant["item" .. idx]
        if item_id and item_id > 0 then
            table.insert(my_items, item_id)
        end
    end

    return {
        match_id = mid,
        champion_id = participant.championId,
        champion_name = participant.championName,
        champion_image = champ_image,
        kills = participant.kills or 0,
        deaths = participant.deaths or 0,
        assists = participant.assists or 0,
        cs = cs,
        cs_per_min = cs_per_min,
        vision_score = participant.visionScore or 0,
        total_damage = participant.totalDamageDealtToChampions or 0,
        gold_earned = participant.goldEarned or 0,
        win = participant.win,
        game_duration = string.format("%d:%02d", duration_min, duration_sec),
        game_duration_raw = game_duration,
        game_mode = info.gameMode,
        position = participant.teamPosition or "",
        queue_id = info.queueId,
        game_creation = info.gameCreation,
        items = my_items,
        summoner1 = participant.summoner1Id or 0,
        summoner2 = participant.summoner2Id or 0,
        -- Multi-kills
        double_kills = participant.doubleKills or 0,
        triple_kills = participant.tripleKills or 0,
        quadra_kills = participant.quadraKills or 0,
        penta_kills = participant.pentaKills or 0,
        -- Damage breakdown
        physical_damage = participant.physicalDamageDealtToChampions or 0,
        magic_damage = participant.magicDamageDealtToChampions or 0,
        true_damage = participant.trueDamageDealtToChampions or 0,
        damage_taken = participant.totalDamageTaken or 0,
        -- Wards
        wards_placed = participant.wardsPlaced or 0,
        wards_killed = participant.wardsKilled or 0,
        control_wards = participant.detectorWardsPlaced or 0,
        -- Challenges per match
        kill_participation = challenges.killParticipation or 0,
        damage_share = challenges.teamDamagePercentage or 0,
        gold_per_min = challenges.goldPerMinute or 0,
        damage_per_min = challenges.damagePerMinute or 0,
        -- Runes
        perks_keystone = keystone,
        perks_primary_style = primary_style,
        perks_sub_style = sub_style,
        champ_level = participant.champLevel or 0,
        gold_spent = participant.goldSpent or 0,
        game_ended_surrender = participant.gameEndedInSurrender or false,
        first_blood = participant.firstBloodKill or false,
        -- Challenges-based stats
        solo_kills = challenges.soloKills or 0,
        turret_plates = challenges.turretPlatesTaken or 0,
        dragon_takedowns = (challenges.dragonTakedowns or 0) > 0 and (challenges.dragonTakedowns or 0)
                or (function()
            if info and info.teams then
                for _, team in ipairs(info.teams) do
                    if team.teamId == participant.teamId and team.objectives and team.objectives.dragon then
                        return team.objectives.dragon.kills or 0
                    end
                end
            end
            return 0
        end)(),
        baron_takedowns = (challenges.baronTakedowns or 0) > 0 and (challenges.baronTakedowns or 0)
                or (function()
            if info and info.teams then
                for _, team in ipairs(info.teams) do
                    if team.teamId == participant.teamId and team.objectives and team.objectives.baron then
                        return team.objectives.baron.kills or 0
                    end
                end
            end
            return 0
        end)(),
        rift_herald_takedowns = (challenges.riftHeraldTakedowns or 0) > 0 and (challenges.riftHeraldTakedowns or 0)
                or (function()
            if info and info.teams then
                for _, team in ipairs(info.teams) do
                    if team.teamId == participant.teamId and team.objectives and team.objectives.riftHerald then
                        return team.objectives.riftHerald.kills or 0
                    end
                end
            end
            return 0
        end)(),
        vision_per_min = challenges.visionScorePerMinute or 0,
        lane_minions_first10 = challenges.laneMinionsFirst10Minutes or 0,
        max_cs_advantage = challenges.maxCsAdvantageOnLaneOpponent or 0,
        max_level_lead = challenges.maxLevelLeadLaneOpponent or 0,
        turret_takedowns = challenges.turretTakedowns or 0,
        inhibitor_takedowns = challenges.inhibitorTakedowns or 0,
        -- Teams
        allies = allies,
        enemies = enemies,
        _raw_participants = all_participants_raw,
    }
end

--- Build match entry from cached DB data.
local function build_cached_match(row, participants, puuid, champions)
    local items = {}
    if row.items and row.items ~= "" then
        local ok, parsed = pcall(json.decode, row.items)
        if ok then items = parsed end
    end

    local champ = champions[tostring(row.champion_id)]
    local champ_image = champ and champ.image or nil

    local game_duration = row.game_duration or 0
    local duration_min = math.floor(game_duration / 60)
    local duration_sec = game_duration % 60
    local cs_per_min = row.cs_per_min or 0

    -- Build allies/enemies from participants
    local allies = {}
    local enemies = {}
    local my_team = nil

    for _, p in ipairs(participants) do
        if p.puuid == puuid then
            my_team = p.team_id
            break
        end
    end

    for _, p in ipairs(participants) do
        local p_champ = champions[tostring(p.champion_id)]
        local player_data = {
            puuid = p.puuid,
            summoner_name = p.summoner_name or "Unknown",
            tag_line = p.tag_line or "",
            champion_name = p.champion_name,
            champion_image = p_champ and p_champ.image or nil,
            kills = p.kills or 0,
            deaths = p.deaths or 0,
            assists = p.assists or 0,
            cs = p.cs or 0,
            total_damage = p.total_damage or 0,
            gold_earned = p.gold_earned or 0,
            vision_score = p.vision_score or 0,
            position = p.position or "",
            win = p.win == 1,
            items = p.items or {},
            summoner1 = p.summoner1 or 0,
            summoner2 = p.summoner2 or 0,
            double_kills = p.double_kills or 0,
            triple_kills = p.triple_kills or 0,
            quadra_kills = p.quadra_kills or 0,
            penta_kills = p.penta_kills or 0,
            physical_damage = p.physical_damage or 0,
            magic_damage = p.magic_damage or 0,
            true_damage = p.true_damage or 0,
            damage_taken = p.damage_taken or 0,
            wards_placed = p.wards_placed or 0,
            wards_killed = p.wards_killed or 0,
            control_wards = p.control_wards or 0,
            kill_participation = p.kill_participation or 0,
            damage_share = p.damage_share or 0,
            perks_keystone = p.perks_keystone or 0,
            perks_primary_style = p.perks_primary_style or 0,
            perks_sub_style = p.perks_sub_style or 0,
            champ_level = p.champ_level or 0,
        }
        if p.puuid == puuid then
            player_data.is_me = true
        end
        if my_team and p.team_id == my_team then
            table.insert(allies, player_data)
        else
            table.insert(enemies, player_data)
        end
    end

    return {
        match_id = row.match_id,
        champion_name = row.champion_name,
        champion_image = champ_image,
        kills = row.kills or 0,
        deaths = row.deaths or 0,
        assists = row.assists or 0,
        cs = row.cs or 0,
        cs_per_min = cs_per_min,
        vision_score = row.vision_score or 0,
        total_damage = row.total_damage or 0,
        gold_earned = row.gold_earned or 0,
        win = row.win == 1,
        game_duration = string.format("%d:%02d", duration_min, duration_sec),
        game_duration_raw = game_duration,
        game_mode = row.game_mode,
        position = row.position or "",
        queue_id = row.queue_id,
        game_creation = row.game_creation,
        items = items,
        summoner1 = row.summoner1 or 0,
        summoner2 = row.summoner2 or 0,
        double_kills = row.double_kills or 0,
        triple_kills = row.triple_kills or 0,
        quadra_kills = row.quadra_kills or 0,
        penta_kills = row.penta_kills or 0,
        physical_damage = row.physical_damage or 0,
        magic_damage = row.magic_damage or 0,
        true_damage = row.true_damage or 0,
        damage_taken = row.damage_taken or 0,
        wards_placed = row.wards_placed or 0,
        wards_killed = row.wards_killed or 0,
        control_wards = row.control_wards or 0,
        kill_participation = row.kill_participation or 0,
        damage_share = row.damage_share or 0,
        gold_per_min = row.gold_per_min or 0,
        damage_per_min = row.damage_per_min or 0,
        perks_keystone = row.perks_keystone or 0,
        perks_primary_style = row.perks_primary_style or 0,
        perks_sub_style = row.perks_sub_style or 0,
        champ_level = row.champ_level or 0,
        game_ended_surrender = (row.game_ended_surrender or 0) == 1,
        first_blood = (row.first_blood or 0) == 1,
        -- Challenges-based stats
        solo_kills = row.solo_kills or 0,
        turret_plates = row.turret_plates or 0,
        dragon_takedowns = row.dragon_takedowns or 0,
        baron_takedowns = row.baron_takedowns or 0,
        rift_herald_takedowns = row.rift_herald_takedowns or 0,
        vision_per_min = row.vision_per_min or 0,
        lane_minions_first10 = row.lane_minions_first10 or 0,
        max_cs_advantage = row.max_cs_advantage or 0,
        max_level_lead = row.max_level_lead or 0,
        turret_takedowns = row.turret_takedowns or 0,
        inhibitor_takedowns = row.inhibitor_takedowns or 0,
        allies = allies,
        enemies = enemies,
    }
end

--- GET /api/search?name=GameName&tag=TagLine
local function handler()
    local res = http.response()
    local req = http.request()

    local game_name = req:query("name")
    local tag_line = req:query("tag")
    local req_platform = req:query("platform")   -- #17 multi-region
    local req_region = req:query("region")         -- #17 multi-region

    if not game_name or game_name == "" or not tag_line or tag_line == "" then
        res:set_status(400)
        res:write_json({error = "name and tag query parameters are required"})
        return
    end

    -- Region mapping (#17): platform -> region
    local PLATFORM_TO_REGION = {
        BR1 = "AMERICAS", LA1 = "AMERICAS", LA2 = "AMERICAS", NA1 = "AMERICAS", OC1 = "AMERICAS",
        EUW1 = "EUROPE", EUN1 = "EUROPE", RU = "EUROPE", TR1 = "EUROPE", ME1 = "EUROPE",
        KR = "ASIA", JP1 = "ASIA",
        PH2 = "SEA", SG2 = "SEA", TH2 = "SEA", TW2 = "SEA", VN2 = "SEA",
    }

    -- Use request params or fall back to env
    local platform = req_platform or env.get("RIOT_PLATFORM") or "EUW1"
    local region = req_region or PLATFORM_TO_REGION[platform] or env.get("RIOT_REGION") or "EUROPE"

    -- Open storage
    local storage, serr = contract.open("app.lc.lib:player_storage")

    -- Get account (always fresh)
    local account, err = funcs.new():call("app.lc:riot_api_get_account", {
        game_name = game_name,
        tag_line = tag_line,
        region = region,
    })

    if err then
        if err == "not_found" then
            res:set_status(404)
            res:write_json({error = "Player not found: " .. game_name .. "#" .. tag_line})
        elseif err == "rate_limited" then
            res:set_status(429)
            res:write_json({error = "Rate limited, try again later"})
        else
            res:set_status(502)
            res:write_json({error = "API error: " .. tostring(err)})
        end
        return
    end

    local puuid = account.puuid

    -- Get summoner, ranked, mastery, challenges (always fresh)
    local summoner, _ = funcs.new():call("app.lc:riot_api_get_summoner", {puuid = puuid, platform = platform})
    local ranked, _ = funcs.new():call("app.lc:riot_api_get_ranked", {puuid = puuid, platform = platform})
    local mastery, _ = funcs.new():call("app.lc:riot_api_get_mastery", {puuid = puuid, count = 20, platform = platform})
    local challenges, _ = funcs.new():call("app.lc:riot_api_get_challenges", {puuid = puuid, region = region})

    -- DDragon data with caching
    local dd_version = "14.5.1"
    local champions = {}
    local items_map = {}
    local runes_map = {}

    -- Helper: check cache, fetch if miss, store
    local function cached_ddragon(key, func_name, args)
        if not serr and storage then
            local cached = storage:get_ddragon_cache({cache_key = key, ttl_hours = 24})
            if cached and cached.data then
                local ok, parsed = pcall(json.decode, cached.data)
                if ok then return parsed, cached.version end
            end
        end
        local result, err = funcs.new():call(func_name, args or {})
        if result and not err then
            if not serr and storage then
                storage:save_ddragon_cache({
                    cache_key = key,
                    data = json.encode(result),
                    version = result.version,
                })
            end
        end
        return result
    end

    local dd_data = cached_ddragon("champions", "app.lc:ddragon_get_champions", {})
    if dd_data then
        dd_version = dd_data.version or dd_version
        if dd_data.champions then
            for k, v in pairs(dd_data.champions) do
                champions[k] = v
            end
        end
    end

    local dd_items = cached_ddragon("items", "app.lc:ddragon_get_items", {})
    if dd_items then items_map = dd_items.items or {} end

    local dd_runes = cached_ddragon("runes", "app.lc:ddragon_get_runes", {})
    if dd_runes then runes_map = dd_runes.runes or {} end

    -- ── Save profile/ranked/mastery/challenges to DB ──────────
    if not serr and storage then
        if summoner then
            storage:save_player({
                puuid = puuid,
                game_name = account.gameName or game_name,
                tag_line = account.tagLine or tag_line,
                summoner_id = summoner.id,
                summoner_level = summoner.summonerLevel,
                profile_icon_id = summoner.profileIconId,
                revision_date = summoner.revisionDate,
                platform = platform,
                region = region,
            })
        end

        if ranked then
            for _, entry in ipairs(ranked) do
                storage:save_ranked({
                    puuid = puuid,
                    queue_type = entry.queueType,
                    tier = entry.tier,
                    rank = entry.rank,
                    league_points = entry.leaguePoints,
                    wins = entry.wins,
                    losses = entry.losses,
                    hot_streak = entry.hotStreak,
                    veteran = entry.veteran,
                    fresh_blood = entry.freshBlood,
                })
                -- Record LP history
                storage:save_ranked_history({
                    puuid = puuid,
                    queue_type = entry.queueType,
                    tier = entry.tier,
                    rank = entry.rank,
                    league_points = entry.leaguePoints,
                    wins = entry.wins,
                    losses = entry.losses,
                })
            end
        end

        if mastery then
            for _, m in ipairs(mastery) do
                storage:save_mastery({
                    puuid = puuid,
                    champion_id = m.championId,
                    champion_level = m.championLevel,
                    champion_points = m.championPoints,
                })
            end
        end

        if challenges and challenges.totalPoints then
            local tp = challenges.totalPoints
            storage:save_challenges({
                puuid = puuid,
                level = tp.level,
                current_points = tp.current,
                max_points = tp.max,
                percentile = tp.percentile,
            })
        end

        storage:save_recent_search({
            puuid = puuid,
            game_name = account.gameName or game_name,
            tag_line = account.tagLine or tag_line,
            summoner_level = summoner and summoner.summonerLevel,
            profile_icon_id = summoner and summoner.profileIconId,
            platform = platform,
        })
    end

    -- ── Enrich mastery ────────────────────────────────────────
    local enriched_mastery = {}
    if mastery then
        for _, m in ipairs(mastery) do
            local champ = champions[tostring(m.championId)]
            table.insert(enriched_mastery, {
                championId = m.championId,
                championLevel = m.championLevel,
                championPoints = m.championPoints,
                championPointsSinceLastLevel = m.championPointsSinceLastLevel,
                championPointsUntilNextLevel = m.championPointsUntilNextLevel,
                lastPlayTime = m.lastPlayTime,
                chestGranted = m.chestGranted,
                champion_name = champ and champ.name or ("Champion " .. m.championId),
                champion_id_str = champ and champ.id or nil,
                champion_image = champ and champ.image or nil,
                champion_title = champ and champ.title or nil,
            })
        end
    end

    -- ── Matches with caching ──────────────────────────────────
    -- Step 1: load ALL cached matches from DB immediately
    local cached_matches_map = {}
    if not serr and storage then
        local db_rows = storage:get_matches({puuid = puuid, limit = 50}) or {}
        local db_ids = {}
        for _, row in ipairs(db_rows) do table.insert(db_ids, row.match_id) end
        local parts_by_match = {}
        if #db_ids > 0 then
            local all_parts = storage:get_match_participants({match_ids = db_ids}) or {}
            for _, p in ipairs(all_parts) do
                if not parts_by_match[p.match_id] then parts_by_match[p.match_id] = {} end
                table.insert(parts_by_match[p.match_id], p)
            end
        end
        for _, row in ipairs(db_rows) do
            local parts = parts_by_match[row.match_id] or {}
            cached_matches_map[row.match_id] = build_cached_match(row, parts, puuid, champions)
        end
    end

    -- Step 2: get recent IDs from Riot API, fetch details only for ones not in DB (cap at 5)
    local match_ids, _ = funcs.new():call("app.lc:riot_api_get_matches", {puuid = puuid, count = 30, region = region})
    if match_ids and #match_ids > 0 then
        local new_ids = {}
        for _, mid in ipairs(match_ids) do
            if not cached_matches_map[mid] then table.insert(new_ids, mid) end
        end
        for i = 1, math.min(#new_ids, 5) do
            local mid = new_ids[i]
            local match_data, merr = funcs.new():call("app.lc:riot_api_get_match", {match_id = mid, region = region})
            if match_data and not merr then
                local entry = build_match_entry(mid, match_data, puuid, champions)
                if entry then
                    -- Save to DB
                    if not serr and storage then
                        storage:save_match({
                            match_id = mid,
                            puuid = puuid,
                            champion_id = entry.champion_id,
                            champion_name = entry.champion_name,
                            kills = entry.kills,
                            deaths = entry.deaths,
                            assists = entry.assists,
                            cs = entry.cs,
                            vision_score = entry.vision_score,
                            total_damage = entry.total_damage,
                            gold_earned = entry.gold_earned,
                            win = entry.win,
                            game_duration = entry.game_duration_raw,
                            game_mode = entry.game_mode,
                            queue_id = entry.queue_id,
                            position = entry.position,
                            items = entry.items,
                            game_creation = entry.game_creation,
                            summoner1 = entry.summoner1,
                            summoner2 = entry.summoner2,
                            cs_per_min = entry.cs_per_min,
                            double_kills = entry.double_kills,
                            triple_kills = entry.triple_kills,
                            quadra_kills = entry.quadra_kills,
                            penta_kills = entry.penta_kills,
                            physical_damage = entry.physical_damage,
                            magic_damage = entry.magic_damage,
                            true_damage = entry.true_damage,
                            damage_taken = entry.damage_taken,
                            wards_placed = entry.wards_placed,
                            wards_killed = entry.wards_killed,
                            control_wards = entry.control_wards,
                            kill_participation = entry.kill_participation,
                            damage_share = entry.damage_share,
                            gold_per_min = entry.gold_per_min,
                            damage_per_min = entry.damage_per_min,
                            perks_primary_style = entry.perks_primary_style,
                            perks_sub_style = entry.perks_sub_style,
                            perks_keystone = entry.perks_keystone,
                            champ_level = entry.champ_level,
                            gold_spent = entry.gold_spent,
                            game_ended_surrender = entry.game_ended_surrender,
                            first_blood = entry.first_blood,
                            solo_kills = entry.solo_kills,
                            turret_plates = entry.turret_plates,
                            dragon_takedowns = entry.dragon_takedowns,
                            baron_takedowns = entry.baron_takedowns,
                            rift_herald_takedowns = entry.rift_herald_takedowns,
                            vision_per_min = entry.vision_per_min,
                            lane_minions_first10 = entry.lane_minions_first10,
                            max_cs_advantage = entry.max_cs_advantage,
                            max_level_lead = entry.max_level_lead,
                            turret_takedowns = entry.turret_takedowns,
                            inhibitor_takedowns = entry.inhibitor_takedowns,
                        })

                        if entry._raw_participants then
                            storage:save_match_participants({
                                match_id = mid,
                                participants = entry._raw_participants,
                            })
                        end
                    end

                    entry._raw_participants = nil
                    entry.champion_id = nil
                    cached_matches_map[mid] = entry
                end
            end
        end
    end

    -- Build final ordered list: all collected matches sorted by game_creation DESC, limit 30
    local matches = {}
    for _, m in pairs(cached_matches_map) do
        table.insert(matches, m)
    end
    table.sort(matches, function(a, b)
        return (a.game_creation or 0) > (b.game_creation or 0)
    end)
    if #matches > 30 then
        local trimmed = {}
        for i = 1, 30 do trimmed[i] = matches[i] end
        matches = trimmed
    end

    -- ── Profile icon URL ──────────────────────────────────────
    local profile_icon_url = nil
    if summoner and summoner.profileIconId then
        profile_icon_url = "https://ddragon.leagueoflegends.com/cdn/" .. dd_version
                .. "/img/profileicon/" .. tostring(summoner.profileIconId) .. ".png"
    end

    -- ── Challenge summary ─────────────────────────────────────
    local challenge_summary = nil
    if challenges and challenges.totalPoints then
        local tp = challenges.totalPoints
        challenge_summary = {
            level = tp.level,
            current = tp.current,
            max = tp.max,
            percentile = tp.percentile,
        }
    end

    -- ── Live game ─────────────────────────────────────────────
    local active_game, _ = funcs.new():call("app.lc:riot_api_get_active_game", {puuid = puuid, platform = platform})
    local live_game = nil
    if active_game and active_game.gameId then
        local live_participants = {}
        if active_game.participants then
            for _, p in ipairs(active_game.participants) do
                local p_champ = champions[tostring(p.championId)]
                local perks_keystone = 0
                local perks_style = 0
                local perks_sub = 0
                if p.perks then
                    perks_style = p.perks.perkStyle or 0
                    perks_sub = p.perks.perkSubStyle or 0
                    if p.perks.perkIds and #p.perks.perkIds > 0 then
                        perks_keystone = p.perks.perkIds[1]
                    end
                end

                -- Try to get ranked data from DB cache
                local p_ranked = nil
                if not serr and storage and p.puuid and p.puuid ~= "" then
                    local p_ranks = storage:get_ranked({puuid = p.puuid})
                    if p_ranks and type(p_ranks) == "table" then
                        for _, pr in ipairs(p_ranks) do
                            if pr.queue_type == "RANKED_SOLO_5x5" then
                                p_ranked = {
                                    tier = pr.tier,
                                    rank = pr.rank,
                                    lp = pr.league_points,
                                    wins = pr.wins,
                                    losses = pr.losses,
                                }
                                break
                            end
                        end
                    end
                end

                table.insert(live_participants, {
                    summoner_name = p.riotId or p.summonerName or "Unknown",
                    puuid = p.puuid or "",
                    champion_name = p_champ and p_champ.name or ("Champion " .. (p.championId or 0)),
                    champion_image = p_champ and p_champ.image or nil,
                    team_id = p.teamId,
                    summoner1 = p.spell1Id or 0,
                    summoner2 = p.spell2Id or 0,
                    perks_keystone = perks_keystone,
                    perks_style = perks_style,
                    perks_sub = perks_sub,
                    ranked = p_ranked,
                })
            end
        end

        -- Banned champions
        local bans = {}
        if active_game.bannedChampions then
            for _, b in ipairs(active_game.bannedChampions) do
                local b_champ = champions[tostring(b.championId)]
                table.insert(bans, {
                    champion_id = b.championId,
                    champion_name = b_champ and b_champ.name or nil,
                    champion_image = b_champ and b_champ.image or nil,
                    team_id = b.teamId,
                    pick_turn = b.pickTurn,
                })
            end
        end

        live_game = {
            game_id = active_game.gameId,
            game_mode = active_game.gameMode,
            game_type = active_game.gameType,
            game_length = active_game.gameLength or 0,
            queue_id = active_game.gameQueueConfigId,
            participants = live_participants,
            bans = bans,
        }
    end

    -- ── Performance stats ─────────────────────────────────────
    local stats = nil
    if #matches > 0 then
        local total_k, total_d, total_a = 0, 0, 0
        local total_cs_min, total_dmg, total_gold, total_vision = 0, 0, 0, 0
        local total_kp, total_ds = 0, 0
        local total_wards_placed, total_wards_killed, total_control = 0, 0, 0
        local total_phys, total_magic, total_true_dmg = 0, 0, 0
        local wins, losses = 0, 0
        local streak = 0
        local streak_type = nil
        local champ_stats = {}
        local role_counts = {}
        local total_pentas, total_quadras, total_triples = 0, 0, 0
        local first_blood_count = 0
        local surrender_count = 0
        local total_duration_win, total_duration_loss = 0, 0
        local total_gold_spent = 0
        local total_damage_taken = 0
        -- Challenges accumulators
        local total_solo_kills = 0
        local total_turret_plates = 0
        local total_dragon_td = 0
        local total_baron_td = 0
        local total_herald_td = 0
        local total_vision_pm = 0
        local total_cs_first10 = 0
        local total_cs_advantage = 0
        local total_level_lead = 0
        local total_turret_td = 0
        local total_inhibitor_td = 0
        local cs_first10_count = 0 -- games with data
        local total_gpm, total_dpm = 0, 0
        local unique_champs = {}
        local spell_combos = {}
        -- Win/loss split accumulators
        local w_k, w_d, w_a, w_cs, w_dmg, w_gold, w_vis, w_kp = 0, 0, 0, 0, 0, 0, 0, 0
        local l_k, l_d, l_a, l_cs, l_dmg, l_gold, l_vis, l_kp = 0, 0, 0, 0, 0, 0, 0, 0
        -- Enemy matchup tracking
        local enemy_matchups = {}
        -- Lane opponent tracking
        local lane_matchups = {}
        -- Ally synergy tracking
        local ally_synergy = {}
        -- Item frequency tracking
        local item_freq = {}

        for i, m in ipairs(matches) do
            total_k = total_k + m.kills
            total_d = total_d + m.deaths
            total_a = total_a + m.assists
            total_cs_min = total_cs_min + (m.cs_per_min or 0)
            total_dmg = total_dmg + m.total_damage
            total_gold = total_gold + m.gold_earned
            total_vision = total_vision + m.vision_score
            total_kp = total_kp + (m.kill_participation or 0)
            total_ds = total_ds + (m.damage_share or 0)
            total_wards_placed = total_wards_placed + (m.wards_placed or 0)
            total_wards_killed = total_wards_killed + (m.wards_killed or 0)
            total_control = total_control + (m.control_wards or 0)
            total_phys = total_phys + (m.physical_damage or 0)
            total_magic = total_magic + (m.magic_damage or 0)
            total_true_dmg = total_true_dmg + (m.true_damage or 0)
            total_pentas = total_pentas + (m.penta_kills or 0)
            total_quadras = total_quadras + (m.quadra_kills or 0)
            total_triples = total_triples + (m.triple_kills or 0)
            if m.win then wins = wins + 1 else losses = losses + 1 end

            -- Advanced stats collection
            if m.first_blood then first_blood_count = first_blood_count + 1 end
            if m.game_ended_surrender then surrender_count = surrender_count + 1 end
            total_gold_spent = total_gold_spent + (m.gold_spent or 0)
            -- Challenges accumulation
            total_solo_kills = total_solo_kills + (m.solo_kills or 0)
            total_turret_plates = total_turret_plates + (m.turret_plates or 0)
            total_dragon_td = total_dragon_td + (m.dragon_takedowns or 0)
            total_baron_td = total_baron_td + (m.baron_takedowns or 0)
            total_herald_td = total_herald_td + (m.rift_herald_takedowns or 0)
            total_vision_pm = total_vision_pm + (m.vision_per_min or 0)
            total_turret_td = total_turret_td + (m.turret_takedowns or 0)
            total_inhibitor_td = total_inhibitor_td + (m.inhibitor_takedowns or 0)
            if (m.lane_minions_first10 or 0) > 0 then
                total_cs_first10 = total_cs_first10 + m.lane_minions_first10
                cs_first10_count = cs_first10_count + 1
            end
            total_cs_advantage = total_cs_advantage + (m.max_cs_advantage or 0)
            total_level_lead = total_level_lead + (m.max_level_lead or 0)
            total_damage_taken = total_damage_taken + (m.damage_taken or 0)
            total_gpm = total_gpm + (m.gold_per_min or 0)
            total_dpm = total_dpm + (m.damage_per_min or 0)
            unique_champs[m.champion_name or "Unknown"] = true
            if m.win then
                total_duration_win = total_duration_win + (m.game_duration_raw or 0)
                w_k = w_k + m.kills; w_d = w_d + m.deaths; w_a = w_a + m.assists
                w_cs = w_cs + (m.cs_per_min or 0); w_dmg = w_dmg + m.total_damage
                w_gold = w_gold + m.gold_earned; w_vis = w_vis + (m.vision_score or 0)
                w_kp = w_kp + (m.kill_participation or 0)
            else
                total_duration_loss = total_duration_loss + (m.game_duration_raw or 0)
                l_k = l_k + m.kills; l_d = l_d + m.deaths; l_a = l_a + m.assists
                l_cs = l_cs + (m.cs_per_min or 0); l_dmg = l_dmg + m.total_damage
                l_gold = l_gold + m.gold_earned; l_vis = l_vis + (m.vision_score or 0)
                l_kp = l_kp + (m.kill_participation or 0)
            end

            -- Spell combo tracking
            local s1 = m.summoner1 or 0
            local s2 = m.summoner2 or 0
            if s1 > s2 then s1, s2 = s2, s1 end
            local combo_key = s1 .. "_" .. s2
            if not spell_combos[combo_key] then
                spell_combos[combo_key] = {s1 = s1, s2 = s2, games = 0, wins = 0}
            end
            spell_combos[combo_key].games = (spell_combos[combo_key].games or 0) + 1
            if m.win then spell_combos[combo_key].wins = (spell_combos[combo_key].wins or 0) + 1 end

            -- Enemy matchup tracking
            if m.enemies then
                for _, e in ipairs(m.enemies) do
                    if e.champion_name then
                        if not enemy_matchups[e.champion_name] then
                            enemy_matchups[e.champion_name] = {games = 0, wins = 0, image = e.champion_image}
                        end
                        enemy_matchups[e.champion_name].games = (enemy_matchups[e.champion_name].games or 0) + 1
                        if m.win then enemy_matchups[e.champion_name].wins = (enemy_matchups[e.champion_name].wins or 0) + 1 end
                    end
                end
            end

            if i == 1 then
                streak_type = m.win and "W" or "L"
                streak = 1
            elseif (m.win and streak_type == "W") or (not m.win and streak_type == "L") then
                streak = streak + 1
            end

            local cn = m.champion_name or "Unknown"
            if not champ_stats[cn] then
                champ_stats[cn] = {wins = 0, losses = 0, kills = 0, deaths = 0, assists = 0, games = 0, image = m.champion_image,
                                   total_cs_min = 0, total_damage = 0, total_gold = 0, total_vision = 0, total_kp = 0, total_ds = 0,
                                   total_phys = 0, total_magic = 0, total_true = 0,
                                   positions = {}, keystones = {}, keystone_wins = {}}
            end
            local cs = champ_stats[cn]
            cs.games = cs.games + 1
            cs.kills = cs.kills + m.kills
            cs.deaths = cs.deaths + m.deaths
            cs.assists = cs.assists + m.assists
            cs.total_cs_min = cs.total_cs_min + (m.cs_per_min or 0)
            cs.total_damage = cs.total_damage + m.total_damage
            cs.total_gold = cs.total_gold + m.gold_earned
            cs.total_vision = cs.total_vision + (m.vision_score or 0)
            cs.total_kp = cs.total_kp + (m.kill_participation or 0)
            cs.total_ds = cs.total_ds + (m.damage_share or 0)
            cs.total_phys = cs.total_phys + (m.physical_damage or 0)
            cs.total_magic = cs.total_magic + (m.magic_damage or 0)
            cs.total_true = cs.total_true + (m.true_damage or 0)
            if m.win then cs.wins = cs.wins + 1 else cs.losses = cs.losses + 1 end
            if m.position and m.position ~= "" then
                cs.positions[m.position] = (cs.positions[m.position] or 0) + 1
            end
            if m.perks_keystone and m.perks_keystone > 0 then
                local ksKey = tostring(m.perks_keystone)
                cs.keystones[ksKey] = (cs.keystones[ksKey] or 0) + 1
                if m.win then cs.keystone_wins[ksKey] = (cs.keystone_wins[ksKey] or 0) + 1 end
            end

            local pos = m.position
            if pos and pos ~= "" then
                role_counts[pos] = (role_counts[pos] or 0) + 1
            end

            -- Lane opponent tracking (enemy in same position)
            if m.position and m.position ~= "" and m.enemies then
                for _, e in ipairs(m.enemies) do
                    if e.position == m.position and e.champion_name then
                        local lk = e.champion_name
                        if not lane_matchups[lk] then
                            lane_matchups[lk] = {games = 0, wins = 0, image = e.champion_image,
                                                 my_kills = 0, my_deaths = 0, opp_kills = 0, opp_deaths = 0}
                        end
                        lane_matchups[lk].games = (lane_matchups[lk].games or 0) + 1
                        if m.win then lane_matchups[lk].wins = (lane_matchups[lk].wins or 0) + 1 end
                        lane_matchups[lk].my_kills = (lane_matchups[lk].my_kills or 0) + m.kills
                        lane_matchups[lk].my_deaths = (lane_matchups[lk].my_deaths or 0) + m.deaths
                        lane_matchups[lk].opp_kills = (lane_matchups[lk].opp_kills or 0) + (e.kills or 0)
                        lane_matchups[lk].opp_deaths = (lane_matchups[lk].opp_deaths or 0) + (e.deaths or 0)
                    end
                end
            end

            -- Champion synergy (ally champions when winning/losing)
            if m.allies then
                for _, a in ipairs(m.allies) do
                    if not a.is_me and a.champion_name then
                        if not ally_synergy[a.champion_name] then
                            ally_synergy[a.champion_name] = {games = 0, wins = 0, image = a.champion_image}
                        end
                        ally_synergy[a.champion_name].games = ally_synergy[a.champion_name].games + 1
                        if m.win then ally_synergy[a.champion_name].wins = ally_synergy[a.champion_name].wins + 1 end
                    end
                end
            end

            -- Item frequency tracking
            if m.items then
                for _, item_id in ipairs(m.items) do
                    if item_id and item_id > 0 then
                        local ik = tostring(item_id)
                        if not item_freq[ik] then
                            item_freq[ik] = {id = item_id, count = 0, wins = 0}
                        end
                        item_freq[ik].count = item_freq[ik].count + 1
                        if m.win then item_freq[ik].wins = item_freq[ik].wins + 1 end
                    end
                end
            end
        end

        local n = #matches
        local avg_kda = total_d > 0 and math.floor((total_k + total_a) / total_d * 10) / 10 or 0

        local champ_list = {}
        for name, cs in pairs(champ_stats) do
            -- Find top position
            local top_pos, top_pos_count = "", 0
            for pos, cnt in pairs(cs.positions) do
                if cnt > top_pos_count then top_pos = pos; top_pos_count = cnt end
            end
            -- Find top keystone
            local top_ks, top_ks_count = 0, 0
            for ks, cnt in pairs(cs.keystones) do
                if cnt > top_ks_count then top_ks = tonumber(ks); top_ks_count = cnt end
            end

            -- All keystones with WR
            local rune_list = {}
            for ks, cnt in pairs(cs.keystones) do
                local ks_wins = cs.keystone_wins[ks] or 0
                table.insert(rune_list, {
                    keystone = tonumber(ks),
                    games = cnt,
                    wins = ks_wins,
                    winrate = math.floor(ks_wins / cnt * 100),
                })
            end
            table.sort(rune_list, function(a, b) return a.games > b.games end)

            -- Damage composition
            local c_dmg_total = cs.total_phys + cs.total_magic + cs.total_true
            local phys_pct = c_dmg_total > 0 and math.floor(cs.total_phys / c_dmg_total * 100) or 0
            local magic_pct = c_dmg_total > 0 and math.floor(cs.total_magic / c_dmg_total * 100) or 0
            local true_pct = c_dmg_total > 0 and (100 - phys_pct - magic_pct) or 0

            table.insert(champ_list, {
                champion_name = name,
                champion_image = cs.image,
                games = cs.games,
                wins = cs.wins,
                losses = cs.losses,
                avg_kda = cs.deaths > 0
                        and math.floor((cs.kills + cs.assists) / cs.deaths * 10) / 10
                        or 0,
                avg_kills = math.floor(cs.kills / cs.games * 10) / 10,
                avg_deaths = math.floor(cs.deaths / cs.games * 10) / 10,
                avg_assists = math.floor(cs.assists / cs.games * 10) / 10,
                avg_cs_min = math.floor(cs.total_cs_min / cs.games * 10) / 10,
                avg_damage = math.floor(cs.total_damage / cs.games),
                avg_gold = math.floor(cs.total_gold / cs.games),
                avg_vision = math.floor(cs.total_vision / cs.games * 10) / 10,
                avg_kp = math.floor(cs.total_kp / cs.games * 1000) / 10,
                avg_ds = math.floor(cs.total_ds / cs.games * 1000) / 10,
                top_position = top_pos,
                top_keystone = top_ks,
                runes = rune_list,
                dmg_physical_pct = phys_pct,
                dmg_magic_pct = magic_pct,
                dmg_true_pct = true_pct,
            })
        end
        table.sort(champ_list, function(a, b) return a.games > b.games end)

        local role_list = {}
        for pos, count in pairs(role_counts) do
            table.insert(role_list, {position = pos, count = count, pct = math.floor(count / n * 100)})
        end
        table.sort(role_list, function(a, b) return a.count > b.count end)

        stats = {
            games = n,
            wins = wins,
            losses = losses,
            winrate = math.floor(wins / n * 100),
            avg_kills = math.floor(total_k / n * 10) / 10,
            avg_deaths = math.floor(total_d / n * 10) / 10,
            avg_assists = math.floor(total_a / n * 10) / 10,
            avg_kda = avg_kda,
            avg_cs_min = math.floor(total_cs_min / n * 10) / 10,
            avg_damage = math.floor(total_dmg / n),
            avg_gold = math.floor(total_gold / n),
            avg_vision = math.floor(total_vision / n * 10) / 10,
            avg_kill_participation = math.floor(total_kp / n * 1000) / 10,
            avg_damage_share = math.floor(total_ds / n * 1000) / 10,
            avg_wards_placed = math.floor(total_wards_placed / n * 10) / 10,
            avg_wards_killed = math.floor(total_wards_killed / n * 10) / 10,
            avg_control_wards = math.floor(total_control / n * 10) / 10,
            total_damage_physical = total_phys,
            total_damage_magic = total_magic,
            total_damage_true = total_true_dmg,
            penta_kills = total_pentas,
            quadra_kills = total_quadras,
            triple_kills = total_triples,
            streak = streak,
            streak_type = streak_type,
            top_champions = champ_list,
            roles = role_list,
            -- Advanced stats
            first_blood_rate = math.floor(first_blood_count / n * 100),
            surrender_rate = math.floor(surrender_count / n * 100),
            avg_duration_win = wins > 0 and math.floor(total_duration_win / wins) or 0,
            avg_duration_loss = losses > 0 and math.floor(total_duration_loss / losses) or 0,
            avg_gold_per_min = math.floor(total_gpm / n * 10) / 10,
            avg_damage_per_min = math.floor(total_dpm / n),
            avg_damage_taken = math.floor(total_damage_taken / n),
            damage_per_gold = total_gold > 0 and math.floor(total_dmg / total_gold * 100) / 100 or 0,
            unique_champions = 0,
            -- Challenges-based averages
            avg_solo_kills = math.floor(total_solo_kills / n * 10) / 10,
            avg_turret_plates = math.floor(total_turret_plates / n * 10) / 10,
            avg_dragon_takedowns = math.floor(total_dragon_td / n * 10) / 10,
            avg_baron_takedowns = math.floor(total_baron_td / n * 10) / 10,
            avg_herald_takedowns = math.floor(total_herald_td / n * 10) / 10,
            avg_vision_per_min = math.floor(total_vision_pm / n * 100) / 100,
            avg_cs_first10 = cs_first10_count > 0 and math.floor(total_cs_first10 / cs_first10_count) or 0,
            avg_cs_advantage = math.floor(total_cs_advantage / n * 10) / 10,
            avg_level_lead = math.floor(total_level_lead / n * 10) / 10,
            avg_turret_takedowns = math.floor(total_turret_td / n * 10) / 10,
            avg_inhibitor_takedowns = math.floor(total_inhibitor_td / n * 10) / 10,
            total_solo_kills = total_solo_kills,
            total_objectives = total_dragon_td + total_baron_td + total_herald_td,
            -- Snowball index: composite of cs advantage + level lead
            snowball_index = math.floor((total_cs_advantage / n + total_level_lead / n * 5) * 10) / 10,
            -- Win/loss split
            win_stats = wins > 0 and {
                avg_kills = math.floor(w_k / wins * 10) / 10,
                avg_deaths = math.floor(w_d / wins * 10) / 10,
                avg_assists = math.floor(w_a / wins * 10) / 10,
                avg_kda = w_d > 0 and math.floor((w_k + w_a) / w_d * 10) / 10 or 0,
                avg_cs_min = math.floor(w_cs / wins * 10) / 10,
                avg_damage = math.floor(w_dmg / wins),
                avg_gold = math.floor(w_gold / wins),
                avg_vision = math.floor(w_vis / wins * 10) / 10,
                avg_kp = math.floor(w_kp / wins * 1000) / 10,
            } or nil,
            loss_stats = losses > 0 and {
                avg_kills = math.floor(l_k / losses * 10) / 10,
                avg_deaths = math.floor(l_d / losses * 10) / 10,
                avg_assists = math.floor(l_a / losses * 10) / 10,
                avg_kda = l_d > 0 and math.floor((l_k + l_a) / l_d * 10) / 10 or 0,
                avg_cs_min = math.floor(l_cs / losses * 10) / 10,
                avg_damage = math.floor(l_dmg / losses),
                avg_gold = math.floor(l_gold / losses),
                avg_vision = math.floor(l_vis / losses * 10) / 10,
                avg_kp = math.floor(l_kp / losses * 1000) / 10,
            } or nil,
        }

        -- Count unique champs
        local uc = 0
        for _ in pairs(unique_champs) do uc = uc + 1 end
        stats.unique_champions = uc

        -- Pool depth classification
        local pool_label = "Versatile"
        if #champ_list > 0 then
            local top_pct = math.floor(champ_list[1].games / n * 100)
            if top_pct >= 60 then pool_label = "One-Trick"
            elseif top_pct >= 40 then pool_label = "Specialist"
            elseif uc <= 3 then pool_label = "Specialist"
            else pool_label = "Versatile" end
        end
        stats.pool_depth = pool_label
        stats.pool_top_pct = #champ_list > 0 and math.floor(champ_list[1].games / n * 100) or 0

        -- Game length preference
        local avg_dur_all = 0
        local short_wins, short_total = 0, 0  -- < 25 min
        local long_wins, long_total = 0, 0    -- > 30 min
        for _, m in ipairs(matches) do
            local dur = m.game_duration_raw or 0
            avg_dur_all = avg_dur_all + dur
            if dur > 0 and dur < 1500 then
                short_total = short_total + 1
                if m.win then short_wins = short_wins + 1 end
            elseif dur >= 1800 then
                long_total = long_total + 1
                if m.win then long_wins = long_wins + 1 end
            end
        end
        stats.avg_game_duration = n > 0 and math.floor(avg_dur_all / n) or 0
        stats.short_game_wr = short_total >= 2 and math.floor(short_wins / short_total * 100) or nil
        stats.short_game_count = short_total
        stats.long_game_wr = long_total >= 2 and math.floor(long_wins / long_total * 100) or nil
        stats.long_game_count = long_total
        local pref_label = "Balanced"
        if stats.short_game_wr and stats.long_game_wr then
            if stats.short_game_wr > stats.long_game_wr + 10 then pref_label = "Early Game"
            elseif stats.long_game_wr > stats.short_game_wr + 10 then pref_label = "Late Game" end
        end
        stats.game_length_pref = pref_label

        -- Spell combos
        local combo_list = {}
        for _, sc in pairs(spell_combos) do
            table.insert(combo_list, sc)
        end
        table.sort(combo_list, function(a, b) return a.games > b.games end)
        stats.spell_combos = combo_list

        -- Enemy matchups (sorted by games)
        local matchup_list = {}
        for name, mu in pairs(enemy_matchups) do
            if mu.games >= 2 then
                table.insert(matchup_list, {
                    champion_name = name,
                    champion_image = mu.image,
                    games = mu.games,
                    wins = mu.wins,
                    losses = mu.games - mu.wins,
                    winrate = math.floor(mu.wins / mu.games * 100),
                })
            end
        end
        table.sort(matchup_list, function(a, b) return a.games > b.games end)
        stats.enemy_matchups = matchup_list

        -- Lane opponent matchups (sorted by games)
        local lane_list = {}
        for name, lm in pairs(lane_matchups) do
            if lm.games >= 2 then
                table.insert(lane_list, {
                    champion_name = name,
                    champion_image = lm.image,
                    games = lm.games,
                    wins = lm.wins,
                    losses = lm.games - lm.wins,
                    winrate = math.floor(lm.wins / lm.games * 100),
                    my_avg_kills = math.floor(lm.my_kills / lm.games * 10) / 10,
                    my_avg_deaths = math.floor(lm.my_deaths / lm.games * 10) / 10,
                    opp_avg_kills = math.floor(lm.opp_kills / lm.games * 10) / 10,
                    opp_avg_deaths = math.floor(lm.opp_deaths / lm.games * 10) / 10,
                })
            end
        end
        table.sort(lane_list, function(a, b) return a.games > b.games end)
        stats.lane_matchups = lane_list

        -- Ally synergy (sorted by games, min 2)
        local synergy_list = {}
        for name, sy in pairs(ally_synergy) do
            if sy.games >= 2 then
                table.insert(synergy_list, {
                    champion_name = name,
                    champion_image = sy.image,
                    games = sy.games,
                    wins = sy.wins,
                    losses = sy.games - sy.wins,
                    winrate = math.floor(sy.wins / sy.games * 100),
                })
            end
        end
        table.sort(synergy_list, function(a, b) return a.games > b.games end)
        stats.ally_synergy = synergy_list

        -- Common items (sorted by frequency, top 15, skip boots/wards/trinkets)
        local item_list = {}
        for _, it in pairs(item_freq) do
            if it.count >= 2 then
                table.insert(item_list, {
                    item_id = it.id,
                    count = it.count,
                    wins = it.wins,
                    losses = it.count - it.wins,
                    winrate = math.floor(it.wins / it.count * 100),
                    pick_rate = math.floor(it.count / n * 100),
                })
            end
        end
        table.sort(item_list, function(a, b) return a.count > b.count end)
        -- Take top 15
        local top_items = {}
        for i = 1, math.min(#item_list, 15) do
            table.insert(top_items, item_list[i])
        end
        stats.common_items = top_items

        -- Recent form (last 5 games)
        local recent_n = math.min(5, n)
        if recent_n > 0 then
            local rf_k, rf_d, rf_a, rf_w, rf_cs, rf_dmg = 0, 0, 0, 0, 0, 0
            for i = 1, recent_n do
                local rm = matches[i]
                rf_k = rf_k + rm.kills
                rf_d = rf_d + rm.deaths
                rf_a = rf_a + rm.assists
                rf_cs = rf_cs + (rm.cs_per_min or 0)
                rf_dmg = rf_dmg + rm.total_damage
                if rm.win then rf_w = rf_w + 1 end
            end
            stats.recent_form = {
                games = recent_n,
                wins = rf_w,
                winrate = math.floor(rf_w / recent_n * 100),
                avg_kda = rf_d > 0 and math.floor((rf_k + rf_a) / rf_d * 10) / 10 or 0,
                avg_kills = math.floor(rf_k / recent_n * 10) / 10,
                avg_deaths = math.floor(rf_d / recent_n * 10) / 10,
                avg_assists = math.floor(rf_a / recent_n * 10) / 10,
                avg_cs_min = math.floor(rf_cs / recent_n * 10) / 10,
                avg_damage = math.floor(rf_dmg / recent_n),
            }
        end
    end

    -- ── Build Recommendations (#20) ───────────────────────
    local build_recs = {}
    if stats and stats.top_champions and #matches > 0 then
        -- For each top champion, find best item combination by WR
        local champ_item_combos = {}
        for _, m in ipairs(matches) do
            local cn = m.champion_name or "Unknown"
            if not champ_item_combos[cn] then champ_item_combos[cn] = {} end
            if m.items then
                -- Sort items to create consistent key (skip boots/trinkets: items < 2000 or wards)
                local core_items = {}
                for _, item_id in ipairs(m.items) do
                    if item_id and item_id >= 3000 then
                        table.insert(core_items, item_id)
                    end
                end
                table.sort(core_items)
                if #core_items >= 2 then
                    -- Use first 3 core items as "build path"
                    local key = ""
                    for ci = 1, math.min(#core_items, 3) do
                        if ci > 1 then key = key .. "," end
                        key = key .. tostring(core_items[ci])
                    end
                    if not champ_item_combos[cn][key] then
                        champ_item_combos[cn][key] = {items = {}, games = 0, wins = 0}
                        for ci = 1, math.min(#core_items, 3) do
                            table.insert(champ_item_combos[cn][key].items, core_items[ci])
                        end
                    end
                    champ_item_combos[cn][key].games = champ_item_combos[cn][key].games + 1
                    if m.win then champ_item_combos[cn][key].wins = champ_item_combos[cn][key].wins + 1 end
                end
            end
        end
        -- Pick best build per champion (by WR, min 2 games)
        for cn, combos in pairs(champ_item_combos) do
            local best_key, best_wr, best_combo = nil, -1, nil
            for k, combo in pairs(combos) do
                if combo.games >= 1 then
                    local wr = combo.wins / combo.games
                    if wr > best_wr or (wr == best_wr and combo.games > (best_combo and best_combo.games or 0)) then
                        best_key = k
                        best_wr = wr
                        best_combo = combo
                    end
                end
            end
            if best_combo then
                table.insert(build_recs, {
                    champion_name = cn,
                    items = best_combo.items,
                    games = best_combo.games,
                    wins = best_combo.wins,
                    winrate = math.floor(best_combo.wins / best_combo.games * 100),
                })
            end
        end
        table.sort(build_recs, function(a, b) return a.games > b.games end)
    end

    -- ── Patch Impact Tracker (#25) ──────────────────────
    local patch_impact = {}
    if #matches > 0 then
        -- Group matches by patch version (extracted from match_id prefix or game_creation date)
        -- Riot match IDs have format: REGION_MATCHNUM, game_creation gives us rough patch dates
        -- We'll use game_creation month as a proxy for patch grouping
        local patch_groups = {}
        for _, m in ipairs(matches) do
            local cn = m.champion_name or "Unknown"
            local gc = m.game_creation or 0
            -- Group by week for recent data
            local week_key = ""
            if gc > 0 then
                week_key = tostring(math.floor(gc / (7 * 24 * 3600 * 1000)))
            else
                week_key = "unknown"
            end

            if not patch_groups[cn] then patch_groups[cn] = {} end
            if not patch_groups[cn][week_key] then
                patch_groups[cn][week_key] = {games = 0, wins = 0, timestamp = gc}
            end
            patch_groups[cn][week_key].games = patch_groups[cn][week_key].games + 1
            if m.win then patch_groups[cn][week_key].wins = patch_groups[cn][week_key].wins + 1 end
        end

        -- Find champions with WR changes over time
        for cn, weeks in pairs(patch_groups) do
            local sorted_weeks = {}
            for wk, data in pairs(weeks) do
                table.insert(sorted_weeks, {week = wk, games = data.games, wins = data.wins, ts = data.timestamp})
            end
            table.sort(sorted_weeks, function(a, b) return a.ts < b.ts end)

            if #sorted_weeks >= 2 then
                local old_total, old_wins = 0, 0
                local new_total, new_wins = 0, 0
                local mid = math.floor(#sorted_weeks / 2)
                for i = 1, mid do
                    old_total = old_total + sorted_weeks[i].games
                    old_wins = old_wins + sorted_weeks[i].wins
                end
                for i = mid + 1, #sorted_weeks do
                    new_total = new_total + sorted_weeks[i].games
                    new_wins = new_wins + sorted_weeks[i].wins
                end
                if old_total >= 2 and new_total >= 2 then
                    local old_wr = math.floor(old_wins / old_total * 100)
                    local new_wr = math.floor(new_wins / new_total * 100)
                    local diff = new_wr - old_wr
                    if math.abs(diff) >= 10 then
                        table.insert(patch_impact, {
                            champion_name = cn,
                            old_wr = old_wr,
                            new_wr = new_wr,
                            diff = diff,
                            old_games = old_total,
                            new_games = new_total,
                        })
                    end
                end
            end
        end
        table.sort(patch_impact, function(a, b) return math.abs(a.diff) > math.abs(b.diff) end)
    end

    -- ── Champion Recommendations (#29) ──────────────────
    local champion_recs = {}
    if stats and stats.top_champions and #stats.top_champions > 0 then
        -- Analyze which champions the player faces and loses to most
        -- Recommend similar champions to their pool they don't play
        local played_champs = {}
        for _, c in ipairs(stats.top_champions) do
            played_champs[c.champion_name] = true
        end

        -- Find champions that allies play well with this player
        -- and champions the player hasn't tried from synergy data
        if stats.ally_synergy then
            for _, sy in ipairs(stats.ally_synergy) do
                if sy.winrate >= 60 and sy.games >= 3 and not played_champs[sy.champion_name] then
                    table.insert(champion_recs, {
                        champion_name = sy.champion_name,
                        champion_image = sy.champion_image,
                        reason = "High synergy (" .. sy.winrate .. "% WR in " .. sy.games .. " games)",
                        score = sy.winrate * sy.games,
                    })
                end
            end
        end

        -- Champions the player loses to often — learn to play them
        if stats.enemy_matchups then
            for _, mu in ipairs(stats.enemy_matchups) do
                if mu.winrate <= 35 and mu.games >= 3 and not played_champs[mu.champion_name] then
                    table.insert(champion_recs, {
                        champion_name = mu.champion_name,
                        champion_image = mu.champion_image,
                        reason = "Counter pick (only " .. mu.winrate .. "% WR against in " .. mu.games .. " games)",
                        score = (100 - mu.winrate) * mu.games,
                    })
                end
            end
        end

        table.sort(champion_recs, function(a, b) return a.score > b.score end)
        -- Top 5 recommendations
        local top_recs = {}
        for i = 1, math.min(#champion_recs, 5) do
            table.insert(top_recs, champion_recs[i])
        end
        champion_recs = top_recs
    end

    -- ── Favorites / Notes / Goals ───────────────────────
    local is_fav = false
    local match_notes = {}
    local goals = {}
    if not serr and storage then
        local fav_result = storage:is_favorite({puuid = puuid})
        if fav_result and fav_result.is_favorite then is_fav = true end
        local notes_result = storage:get_match_notes({puuid = puuid})
        if notes_result and notes_result.notes then match_notes = notes_result.notes end
        local goals_result = storage:get_goals({puuid = puuid})
        if goals_result and goals_result.goals then goals = goals_result.goals end
    end

    -- ── Rank Percentile Estimation (#21) ────────────────
    local rank_percentile = nil
    if ranked then
        -- Approximate rank percentiles based on Riot's published distribution
        local RANK_PERCENTILES = {
            IRON = {IV = 97, III = 95, II = 93, I = 91},
            BRONZE = {IV = 88, III = 85, II = 82, I = 78},
            SILVER = {IV = 73, III = 68, II = 62, I = 56},
            GOLD = {IV = 50, III = 44, II = 38, I = 33},
            PLATINUM = {IV = 28, III = 23, II = 19, I = 15},
            EMERALD = {IV = 12, III = 9, II = 7, I = 5},
            DIAMOND = {IV = 3.5, III = 2.5, II = 1.5, I = 0.8},
            MASTER = {I = 0.3},
            GRANDMASTER = {I = 0.05},
            CHALLENGER = {I = 0.01},
        }
        for _, r in ipairs(ranked) do
            if r.queueType == "RANKED_SOLO_5x5" and r.tier then
                local tier_data = RANK_PERCENTILES[r.tier]
                if tier_data then
                    local div = r.rank or "IV"
                    rank_percentile = tier_data[div] or tier_data["I"] or 50
                end
            end
        end
    end

    -- ── Enrich ranked with extra fields ─────────────────────
    local enriched_ranked = {}
    if ranked then
        for _, r in ipairs(ranked) do
            table.insert(enriched_ranked, {
                queueType = r.queueType,
                tier = r.tier,
                rank = r.rank,
                leaguePoints = r.leaguePoints,
                wins = r.wins,
                losses = r.losses,
                hotStreak = r.hotStreak or false,
                veteran = r.veteran or false,
                freshBlood = r.freshBlood or false,
            })
        end
    end

    -- ── Response ──────────────────────────────────────────────
    res:set_status(200)
    res:write_json({
        account = {
            puuid = puuid,
            game_name = account.gameName,
            tag_line = account.tagLine,
        },
        summoner = summoner and {
            level = summoner.summonerLevel,
            profile_icon_id = summoner.profileIconId,
            profile_icon_url = profile_icon_url,
        } or nil,
        ranked = enriched_ranked,
        mastery = enriched_mastery,
        matches = matches,
        challenges = challenge_summary,
        live_game = live_game,
        stats = stats,
        dd_version = dd_version,
        items_data = items_map,
        runes_data = runes_map,
        -- Level 4 & 5 additions
        is_favorite = is_fav,
        match_notes = match_notes,
        goals = goals,
        build_recommendations = build_recs,
        patch_impact = patch_impact,
        champion_recommendations = champion_recs,
        rank_percentile = rank_percentile,
        platform = platform,
        region = region,
    })
end

return {handler = handler}