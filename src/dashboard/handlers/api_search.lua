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

    local info = match_data.info or {}
    local cs = (participant.totalMinionsKilled or 0) + (participant.neutralMinionsKilled or 0)
    local game_duration = info.gameDuration or 0
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

    if not game_name or game_name == "" or not tag_line or tag_line == "" then
        res:set_status(400)
        res:write_json({error = "name and tag query parameters are required"})
        return
    end

    -- Open storage
    local storage, serr = contract.open("app.lc.lib:player_storage")

    -- Get account (always fresh)
    local account, err = funcs.new():call("app.lc:riot_api_get_account", {
        game_name = game_name,
        tag_line = tag_line,
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
    local summoner, _ = funcs.new():call("app.lc:riot_api_get_summoner", {puuid = puuid})
    local ranked, _ = funcs.new():call("app.lc:riot_api_get_ranked", {puuid = puuid})
    local mastery, _ = funcs.new():call("app.lc:riot_api_get_mastery", {puuid = puuid, count = 20})
    local challenges, _ = funcs.new():call("app.lc:riot_api_get_challenges", {puuid = puuid})

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
        champions = dd_data.champions or {}
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
                platform = env.get("RIOT_PLATFORM") or "EUW1",
                region = env.get("RIOT_REGION") or "EUROPE",
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
            platform = env.get("RIOT_PLATFORM") or "EUW1",
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
    local match_ids, _ = funcs.new():call("app.lc:riot_api_get_matches", {puuid = puuid, count = 20})

    local matches = {}
    if match_ids and #match_ids > 0 then
        local existing = {}
        if not serr and storage then
            existing = storage:check_existing_matches({match_ids = match_ids}) or {}
        end

        local new_ids = {}
        local cached_ids = {}
        for _, mid in ipairs(match_ids) do
            if existing[mid] then
                table.insert(cached_ids, mid)
            else
                table.insert(new_ids, mid)
            end
        end

        -- Load cached matches from DB
        local cached_matches_map = {}
        if #cached_ids > 0 and not serr and storage then
            local cached_rows = storage:get_matches({puuid = puuid, limit = 100}) or {}
            local all_participants = storage:get_match_participants({match_ids = cached_ids}) or {}

            local parts_by_match = {}
            for _, p in ipairs(all_participants) do
                if not parts_by_match[p.match_id] then
                    parts_by_match[p.match_id] = {}
                end
                table.insert(parts_by_match[p.match_id], p)
            end

            -- Move matches without participants to new_ids for re-fetch
            local still_cached = {}
            for _, mid in ipairs(cached_ids) do
                if parts_by_match[mid] and #parts_by_match[mid] > 0 then
                    table.insert(still_cached, mid)
                else
                    table.insert(new_ids, mid)
                end
            end
            cached_ids = still_cached

            for _, row in ipairs(cached_rows) do
                if parts_by_match[row.match_id] then
                    local parts = parts_by_match[row.match_id]
                    cached_matches_map[row.match_id] = build_cached_match(row, parts, puuid, champions)
                end
            end
        end

        -- Fetch only NEW matches from API
        for _, mid in ipairs(new_ids) do
            local match_data, merr = funcs.new():call("app.lc:riot_api_get_match", {match_id = mid})
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

        -- Build final ordered list
        for _, mid in ipairs(match_ids) do
            if cached_matches_map[mid] then
                table.insert(matches, cached_matches_map[mid])
            end
        end
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
    local active_game, _ = funcs.new():call("app.lc:riot_api_get_active_game", {puuid = puuid})
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
                    positions = {}, keystones = {}}
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
            if m.win then cs.wins = cs.wins + 1 else cs.losses = cs.losses + 1 end
            if m.position and m.position ~= "" then
                cs.positions[m.position] = (cs.positions[m.position] or 0) + 1
            end
            if m.perks_keystone and m.perks_keystone > 0 then
                local ksKey = tostring(m.perks_keystone)
                cs.keystones[ksKey] = (cs.keystones[ksKey] or 0) + 1
            end

            local pos = m.position
            if pos and pos ~= "" then
                role_counts[pos] = (role_counts[pos] or 0) + 1
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
        }
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
    })
end

return {handler = handler}
