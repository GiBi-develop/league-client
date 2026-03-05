# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Language:** Lua (business logic) + YAML (registry configuration)
**Runtime:** Wippy (`wippy run` to start)
**No traditional package manager, build step, test framework, or linter.**

This is a League of Legends player lookup dashboard. It fetches player data from Riot Games API,
caches it in SQLite, and serves a web dashboard with real-time WebSocket updates.

### Lint

```bash
wippy lint                    # Errors and warnings
wippy lint --level hint       # All diagnostics
wippy lint --ns app.lc        # Lint only this project's namespace
```

### Registry inspection

```bash
wippy registry list                               # All entries
wippy registry list --kind "function.lua"         # Only functions
wippy registry list --ns app.lc                   # Only this project's entries
wippy registry show app.lc:supervisor             # Show entry details
```

## Running

```bash
wippy run
```

All services auto-start via `process.service` with `auto_start: true`.

## Architecture

Four cooperating services communicate via an event bus (`"league_client"` channel):

```
Supervisor  →  spawns N Fetcher processes (one per tracked player)
Fetcher     →  calls Riot API, emits "player.data_fetched" event
Data Manager  →  subscribes to events, compares data, writes to DB
Discord Notifier →  subscribes to events, sends webhook on rank changes
```

### Key Components

| File                          | Role                                                              |
|-------------------------------|-------------------------------------------------------------------|
| `src/supervisor.lua`          | Discovers tracked players via registry, spawns/restarts fetchers  |
| `src/fetcher.lua`             | Timer loop per player; calls Riot API, emits events               |
| `src/data_manager.lua`        | Single DB writer; handles data comparison and change detection    |
| `src/discord_notifier.lua`    | Subscribes to events, sends Discord webhook on changes            |
| `src/lib/players.lua`         | SQLite CRUD contract for player data                              |
| `src/api/riot_api.lua`        | Riot Games API client functions                                   |
| `src/api/data_dragon.lua`     | Data Dragon static data client (champions, items, icons)          |
| `src/dashboard/`              | Web UI with WebSocket real-time updates                           |
| `src/_index.yaml`             | Root registry: namespace `app.lc`, DB, services                   |

### Riot API Integration

API calls use two routing types:
- **Platform** (`{platform}.api.riotgames.com`): Summoner, League, Champion Mastery
- **Regional** (`{region}.api.riotgames.com`): Account, Match

Environment variables: `RIOT_API_KEY`, `RIOT_PLATFORM` (default: EUW1), `RIOT_REGION` (default: EUROPE).

### Event Bus Contract

Events published to `"league_client"` channel:

- `player.data_fetched` — fetcher retrieved player data (summoner, ranked, mastery, matches)
- `player.rank_changed` — player rank changed (old_rank → new_rank)
- `player.match_new` — new match detected for tracked player
- `fetch.failed` — API call failed

### Adding a Tracked Player

Add an entry to `src/_index.yaml` with meta.type: "player":

```yaml
- name: player_faker
  kind: registry.entry
  meta:
    type: player
    game_name: Hide on bush
    tag_line: KR1
    fetch_interval: "10m"
```

Restart the service → supervisor discovers it → fetcher spawned automatically.

## Environment

`.env` file supports:
- `RIOT_API_KEY` — Riot Games API key (required)
- `RIOT_PLATFORM` — Platform routing (EUW1, NA1, KR, etc.)
- `RIOT_REGION` — Regional routing (EUROPE, AMERICAS, ASIA)
- `DISCORD_WEBHOOK_URL` — Discord webhook URL for notifications

## Wippy Documentation

- Docs site: https://wippy.ai/
- LLM-friendly index: https://wippy.ai/llms.txt
- Batch fetch pages: `https://wippy.ai/llm/context?paths=<comma-separated-paths>`
- Search: `https://wippy.ai/llm/search?q=<query>`
