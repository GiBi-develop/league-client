local http = require("http")
local renderer = require("renderer")

--- GET / — render the league client dashboard via Jet template
local function handler()
    local res = http.response()

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
