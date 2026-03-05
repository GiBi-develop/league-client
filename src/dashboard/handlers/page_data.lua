--- Data function for the dashboard page template.
local function handler(context)
    return {
        title = "League Client Dashboard",
        ws_url = "ws://localhost:80/ws/updates",
    }
end

return { handler = handler }
