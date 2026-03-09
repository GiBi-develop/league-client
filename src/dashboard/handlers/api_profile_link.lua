local http = require("http")
local contract = require("contract")

--- GET /p/{name}-{tag}-{platform} — Shareable profile link (#30).
--- Redirects to main page with search params, or returns JSON if Accept: application/json.
local function handler()
    local res = http.response()
    local req = http.request()

    -- Parse the composite path parameter
    local slug = req:param("slug")
    if not slug or slug == "" then
        res:set_status(400)
        res:write_json({error = "invalid profile link"})
        return
    end

    -- Slug format: "Name-Tag-Platform" (last two segments after last dashes)
    -- Find platform (last segment)
    local parts = {}
    for part in string.gmatch(slug, "[^-]+") do
        table.insert(parts, part)
    end

    if #parts < 3 then
        res:set_status(400)
        res:write_json({error = "invalid profile link format, expected: Name-Tag-Platform"})
        return
    end

    local platform = parts[#parts]
    local tag = parts[#parts - 1]
    -- Name is everything before tag-platform
    local name_parts = {}
    for i = 1, #parts - 2 do
        table.insert(name_parts, parts[i])
    end
    local name = table.concat(name_parts, " ")

    -- Check Accept header for JSON API usage
    local accept = req:header("Accept") or ""
    if string.find(accept, "application/json", 1, true) then
        -- Return profile data as JSON
        local storage, serr = contract.open("app.lc.lib:player_storage")
        if serr then
            res:set_status(500)
            res:write_json({error = "storage unavailable"})
            return
        end
        -- Try to find player in cache by name
        res:set_status(200)
        res:write_json({name = name, tag = tag, platform = platform})
        return
    end

    -- Redirect to dashboard with search params
    -- URL-encode spaces and special chars in name
    local encoded_name = string.gsub(name, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    local encoded_tag = string.gsub(tag, "([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    local redirect_url = "/?player=" .. encoded_name .. "%23" .. encoded_tag .. "&platform=" .. platform
    res:set_status(302)
    res:set_header("Location", redirect_url)
    return
end

return {handler = handler}
