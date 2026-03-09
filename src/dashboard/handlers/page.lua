local http = require("http")
local renderer = require("renderer")
local env = require("env")
local base64 = require("base64")

--- GET / — render the league client dashboard via Jet template
--- If DASHBOARD_PASSWORD is set, requires HTTP Basic Auth (any username, matching password).
local function handler()
    local res = http.response()
    local req = http.request()

    -- Basic Auth guard: only active when DASHBOARD_PASSWORD env var is set
    local password = env.get("DASHBOARD_PASSWORD")
    if password and password ~= "" then
        local auth = req:header("Authorization") or ""
        local ok = false
        local prefix = "Basic "
        if auth:sub(1, #prefix) == prefix then
            local decoded = base64.decode(auth:sub(#prefix + 1)) or ""
            local colon = decoded:find(":")
            if colon and decoded:sub(colon + 1) == password then
                ok = true
            end
        end
        if not ok then
            res:set_status(401)
            res:set_header("WWW-Authenticate", 'Basic realm="League Client"')
            res:set_content_type("text/plain")
            res:write("Unauthorized")
            return
        end
    end

    local content, err = renderer.render("app.lc.dashboard:dashboard_page", {}, {})
    if err then
        res:set_status(500)
        res:write("Render error: " .. tostring(err))
        return
    end

    res:set_content_type("text/html")
    res:write(tostring(content))
end

return { handler = handler }
