local http_client = require("http_client")
local json = require("json")
local env = require("env")

--- Build request headers with API key.
local function api_headers()
    local key = env.get("RIOT_API_KEY")
    if not key or key == "" then
        error("RIOT_API_KEY is not set")
    end
    return {
        ["X-Riot-Token"] = key,
        ["Accept"] = "application/json",
        ["User-Agent"] = "wippy-league-client/1.0",
    }
end

--- Get platform from env or meta, default EUW1.
local function get_platform(meta)
    if meta and meta.platform then return meta.platform end
    local p = env.get("RIOT_PLATFORM")
    if p and p ~= "" then return p end
    return "EUW1"
end

--- Get region from env or meta, default EUROPE.
local function get_region(meta)
    if meta and meta.region then return meta.region end
    local r = env.get("RIOT_REGION")
    if r and r ~= "" then return r end
    return "EUROPE"
end

--- Make an API request and return parsed JSON.
local function api_request(url)
    local resp, err = http_client.get(url, {
        headers = api_headers(),
        timeout = "15s",
    })

    if err then
        return nil, "HTTP request failed: " .. tostring(err)
    end

    if resp.status_code == 404 then
        return nil, "not_found"
    end

    if resp.status_code == 429 then
        return nil, "rate_limited"
    end

    if resp.status_code ~= 200 then
        return nil, "API returned " .. resp.status_code .. ": " .. (resp.body or "")
    end

    local data = json.decode(resp.body)
    return data
end

--- Get account by Riot ID (gameName#tagLine).
--- Input: {game_name = "...", tag_line = "...", region? = "EUROPE"}
--- Returns: {puuid, gameName, tagLine}
local function get_account(meta)
    if not meta or not meta.game_name or not meta.tag_line then
        return nil, "game_name and tag_line are required"
    end

    local region = get_region(meta)
    local url = "https://" .. string.lower(region) .. ".api.riotgames.com"
        .. "/riot/account/v1/accounts/by-riot-id/"
        .. meta.game_name .. "/" .. meta.tag_line

    return api_request(url)
end

--- Get summoner by PUUID.
--- Input: {puuid = "...", platform? = "EUW1"}
--- Returns: {id, accountId, puuid, profileIconId, revisionDate, summonerLevel}
local function get_summoner(meta)
    if not meta or not meta.puuid then
        return nil, "puuid is required"
    end

    local platform = get_platform(meta)
    local url = "https://" .. string.lower(platform) .. ".api.riotgames.com"
        .. "/lol/summoner/v4/summoners/by-puuid/" .. meta.puuid

    return api_request(url)
end

--- Get ranked entries by PUUID.
--- Input: {puuid = "...", platform? = "EUW1"}
--- Returns: array of {queueType, tier, rank, leaguePoints, wins, losses, ...}
local function get_ranked(meta)
    if not meta or not meta.puuid then
        return nil, "puuid is required"
    end

    local platform = get_platform(meta)
    local url = "https://" .. string.lower(platform) .. ".api.riotgames.com"
        .. "/lol/league/v4/entries/by-puuid/" .. meta.puuid

    return api_request(url)
end

--- Get top champion mastery by PUUID.
--- Input: {puuid = "...", count? = 5, platform? = "EUW1"}
--- Returns: array of {championId, championLevel, championPoints, ...}
local function get_mastery(meta)
    if not meta or not meta.puuid then
        return nil, "puuid is required"
    end

    local count = meta.count or 5
    local platform = get_platform(meta)
    local url = "https://" .. string.lower(platform) .. ".api.riotgames.com"
        .. "/lol/champion-mastery/v4/champion-masteries/by-puuid/" .. meta.puuid
        .. "/top?count=" .. count

    return api_request(url)
end

--- Get match IDs by PUUID.
--- Input: {puuid = "...", count? = 10, region? = "EUROPE"}
--- Returns: array of match ID strings
local function get_matches(meta)
    if not meta or not meta.puuid then
        return nil, "puuid is required"
    end

    local count = meta.count or 10
    local region = get_region(meta)
    local url = "https://" .. string.lower(region) .. ".api.riotgames.com"
        .. "/lol/match/v5/matches/by-puuid/" .. meta.puuid
        .. "/ids?count=" .. count

    return api_request(url)
end

--- Get match details by match ID.
--- Input: {match_id = "...", region? = "EUROPE"}
--- Returns: full match data object
local function get_match(meta)
    if not meta or not meta.match_id then
        return nil, "match_id is required"
    end

    local region = get_region(meta)
    local url = "https://" .. string.lower(region) .. ".api.riotgames.com"
        .. "/lol/match/v5/matches/" .. meta.match_id

    return api_request(url)
end

--- Get player challenges data by PUUID.
--- Input: {puuid = "...", platform? = "EUW1"}
--- Returns: {totalPoints, categoryPoints, preferences, challenges}
local function get_challenges(meta)
    if not meta or not meta.puuid then
        return nil, "puuid is required"
    end

    local platform = get_platform(meta)
    local url = "https://" .. string.lower(platform) .. ".api.riotgames.com"
        .. "/lol/challenges/v1/player-data/" .. meta.puuid

    return api_request(url)
end

return {
    get_account = get_account,
    get_summoner = get_summoner,
    get_ranked = get_ranked,
    get_mastery = get_mastery,
    get_matches = get_matches,
    get_match = get_match,
    get_challenges = get_challenges,
}
