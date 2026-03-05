# League Client — Player Lookup Dashboard

Сервис для поиска и отображения информации об игроках League of Legends.
Работает как демон на сервере через wippy, периодически обновляет кэш данных.

## Возможности

- Поиск игрока по Riot ID (gameName#tagLine)
- Профиль: уровень, иконка, дата последней активности
- Ранги во всех очередях (Solo/Duo, Flex)
- Топ чемпионы по мастерству
- Последние матчи с детальной статистикой (KDA, CS, урон, предметы)
- Веб-дашборд с real-time обновлениями через WebSocket
- Кэширование данных в SQLite
- Discord уведомления (опционально)

## Riot Games API — Используемые эндпоинты

| API | Endpoint | Назначение |
|-----|----------|------------|
| Account V1 | `GET /riot/account/v1/accounts/by-riot-id/{gameName}/{tagLine}` | Поиск аккаунта по Riot ID |
| Summoner V4 | `GET /lol/summoner/v4/summoners/by-puuid/{puuid}` | Уровень, иконка профиля |
| League V4 | `GET /lol/league/v4/entries/by-puuid/{puuid}` | Ранги (тир, дивизион, LP, W/L) |
| Champion Mastery V4 | `GET /lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}/top` | Топ чемпионы по мастерству |
| Match V5 | `GET /lol/match/v5/matches/by-puuid/{puuid}/ids` | Список матчей |
| Match V5 | `GET /lol/match/v5/matches/{matchId}` | Детали матча |
| Champion V3 | `GET /lol/platform/v3/champion-rotations` | Бесплатная ротация |

### Routing

- **Platform routing** (`{platform}.api.riotgames.com`): Summoner, League, Champion Mastery, Champion, Spectator
- **Regional routing** (`{region}.api.riotgames.com`): Account, Match

### Rate Limits (Development Key)

- 20 запросов/сек, 100 запросов/2 мин
- Ключ истекает каждые 24ч

---

## Riot Games API — Полный список доступных эндпоинтов

### Account V1 (Regional: AMERICAS, EUROPE, ASIA, SEA)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/riot/account/v1/accounts/by-puuid/{puuid}` | Аккаунт по PUUID |
| GET | `/riot/account/v1/accounts/by-riot-id/{gameName}/{tagLine}` | Аккаунт по Riot ID |
| GET | `/riot/account/v1/accounts/me` | Аккаунт по access token (RSO) |

### Summoner V4 (Platform: NA1, EUW1, EUN1, KR, etc.)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/summoner/v4/summoners/by-puuid/{puuid}` | Summoner (level, icon, revision) |

### Champion Mastery V4 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}` | Все мастерства |
| GET | `/lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}/by-champion/{championId}` | Мастерство по чемпиону |
| GET | `/lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}/top` | Топ N мастерств |
| GET | `/lol/champion-mastery/v4/scores/by-puuid/{puuid}` | Суммарный уровень мастерства |

### Champion V3 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/platform/v3/champion-rotations` | Бесплатная ротация чемпионов |

### League V4 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/league/v4/entries/by-puuid/{puuid}` | Ранги игрока по всем очередям |
| GET | `/lol/league/v4/entries/{queue}/{tier}/{division}` | Игроки по рангу (paginated) |
| GET | `/lol/league/v4/challengerleagues/by-queue/{queue}` | Challenger лига |
| GET | `/lol/league/v4/grandmasterleagues/by-queue/{queue}` | Grandmaster лига |
| GET | `/lol/league/v4/masterleagues/by-queue/{queue}` | Master лига |

### Match V5 (Regional)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/match/v5/matches/by-puuid/{puuid}/ids` | Список ID матчей (фильтры: queue, type, start/end time, count) |
| GET | `/lol/match/v5/matches/{matchId}` | Полные данные матча (участники, стата, предметы, руны) |
| GET | `/lol/match/v5/matches/{matchId}/timeline` | Таймлайн матча (позиции, ивенты) |

### Spectator V5 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/spectator/v5/active-games/by-summoner/{puuid}` | Текущая live-игра |

### Clash V1 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/clash/v1/players/by-puuid/{puuid}` | Clash-информация игрока |
| GET | `/lol/clash/v1/tournaments` | Активные/предстоящие турниры |

### Challenges V1 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/challenges/v1/challenges/config` | Конфигурация челленджей |
| GET | `/lol/challenges/v1/player-data/{puuid}` | Прогресс челленджей игрока |

### Status V4 (Platform)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/lol/status/v4/platform-data` | Статус серверов |

### Data Dragon (без ключа)
| Resource | URL |
|----------|-----|
| Версии | `https://ddragon.leagueoflegends.com/api/versions.json` |
| Чемпионы | `https://ddragon.leagueoflegends.com/cdn/{ver}/data/{lang}/champion.json` |
| Предметы | `https://ddragon.leagueoflegends.com/cdn/{ver}/data/{lang}/item.json` |
| Изображения чемпионов | `https://ddragon.leagueoflegends.com/cdn/{ver}/img/champion/{Name}.png` |
| Иконки профиля | `https://ddragon.leagueoflegends.com/cdn/{ver}/img/profileicon/{id}.png` |

---

## Возможные проекты на базе Riot API

### 1. Player Lookup Dashboard (реализовано)
Поиск игрока, профиль, ранги, мастерство, матчи, веб-дашборд.

### 2. Match History Analyzer
Глубокий анализ: винрейт по чемпионам/ролям, KDA тренды, сравнение игроков.

### 3. Live Game Tracker
Мониторинг live-игры: ранги всех 10 участников, мастерство на чемпионах, винрейт.

### 4. Free Rotation Tracker
Мониторинг ротации бесплатных чемпионов, Discord-уведомления.

### 5. Ranked Leaderboard Monitor
Отслеживание Challenger/GM/Master лидербордов, LP-изменения.

### 6. Challenge Progress Tracker
Прогресс челленджей, перцентили, ближайшие к следующему уровню.

### 7. Server Status Monitor
Мониторинг статуса серверов, уведомления при инцидентах.

---

## Architecture

```
┌─ Registry (_index.yaml) ───────────────────────────────────────────┐
│  Tracked players: registry entries with meta.type = "player"       │
│  API functions: riot_api.lua                                       │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ registry.find({meta.type: "player"})
                       ▼
┌─ Player Supervisor (process.service, auto_start) ──────────────────┐
│  Discovers tracked player entries → spawns Fetcher per player       │
│  Restarts crashed fetchers (let-it-crash supervision)               │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ spawn_monitored("app.lc:fetcher", ...)
                       ▼
┌─ Fetcher Process (per player) ─────────────────────────────────────┐
│  Timer: раз в 10 мин                                                │
│  1. funcs.call(riot_api) → summoner, ranked, mastery, matches      │
│  2. events.send("league_client", "player.updated", ...)            │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ event: player.updated
                       ▼
┌─ Data Manager (process.service, auto_start) ───────────────────────┐
│  Subscribes to "league_client" events                               │
│  Stores/updates player data in SQLite                               │
│  Emits "player.rank_changed", "player.match_new" events            │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ events
                       ▼
┌─ Consumers ────────────────────────────────────────────────────────┐
│  - HTTP Dashboard (WebSocket real-time)                             │
│  - Discord Notifier (rank changes, new matches)                     │
└────────────────────────────────────────────────────────────────────┘
```

## Running

```bash
wippy run
```

All services auto-start via `process.service` with `auto_start: true`.

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `RIOT_API_KEY` | Riot Games API key | Yes |
| `RIOT_PLATFORM` | Platform (EUW1, NA1, KR, etc.) | Yes (default: EUW1) |
| `RIOT_REGION` | Region (EUROPE, AMERICAS, ASIA) | Yes (default: EUROPE) |
| `DISCORD_WEBHOOK_URL` | Discord webhook for notifications | No |

## Configuration

`.env`:
```
RIOT_API_KEY=RGAPI-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
RIOT_PLATFORM=EUW1
RIOT_REGION=EUROPE
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```
