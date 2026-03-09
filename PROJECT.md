# League Client — Полная документация проекта

## Обзор

League Client — веб-дашборд для поиска и отслеживания игроков League of Legends. Построен на фреймворке **Wippy** (Lua + YAML), использует Riot Games API для получения данных, кэширует их в SQLite, и предоставляет real-time обновления через WebSocket.

**Язык:** Lua (бизнес-логика) + YAML (конфигурация реестра)
**Runtime:** Wippy (`wippy run` для запуска)
**База данных:** SQLite (автоматическая миграция)
**Нет:** npm, pip, package manager, build step, test framework

---

## Структура файлов

```
league-client/
├── .env                          # Переменные окружения (API ключ, платформа, регион)
├── .env.example                  # Пример .env
├── CLAUDE.md                     # Инструкции для AI-агента
├── PROJECT.md                    # Этот документ
├── context.yaml                  # Конфигурация контекста (Wippy docs)
│
└── src/
    ├── _index.yaml               # Корневой реестр (namespace: app.lc)
    │
    ├── api/
    │   ├── riot_api.lua          # Riot Games API клиент (17 методов)
    │   └── data_dragon.lua       # Data Dragon клиент (4 метода)
    │
    ├── lib/
    │   ├── _index.yaml           # Контракт player_storage (определение + привязка)
    │   └── players.lua           # SQLite CRUD (68 функций, 20 таблиц)
    │
    ├── supervisor.lua            # Супервизор: обнаруживает игроков, спавнит фетчеры
    ├── fetcher.lua               # Фетчер (один на игрока): таймер, Riot API, события
    ├── data_manager.lua          # Менеджер данных: подписка на события, запись в БД
    ├── discord_notifier.lua      # Discord вебхуки: уведомления + retry queue
    ├── telegram_notifier.lua     # Telegram бот: уведомления о рангах и матчах
    ├── weekly_digest.lua         # Еженедельный дайджест (Discord, воскресенье 9:00 UTC)
    │
    ├── templates/
    │   └── layout.jet            # Базовый HTML шаблон
    │
    └── dashboard/
        ├── _index.yaml           # Конфигурация дашборда (роуты, WebSocket)
        ├── dashboard.jet         # Главный UI шаблон (~3000+ строк: HTML + CSS + JS)
        ├── session.lua           # WebSocket сессия (per-client, real-time)
        │
        └── handlers/
            ├── page.lua              # GET / — рендер страницы (+ HTTP Basic Auth)
            ├── page_data.lua         # Данные для шаблона
            ├── ws_connect.lua        # WebSocket upgrade handler
            ├── api_search.lua        # GET /api/search — поиск игрока (~1577 строк)
            ├── api_player.lua        # GET /api/player/{puuid} — профиль из кэша
            ├── api_player_stats.lua  # GET /api/player/{puuid}/stats — расширенная статистика
            ├── api_recent_searches.lua  # GET /api/recent-searches
            ├── api_rotations.lua     # GET /api/rotations — ротация чемпионов
            ├── api_status.lua        # GET /api/status — статус серверов
            ├── api_match_timeline.lua # GET /api/match/{matchId}/timeline
            ├── api_favorites.lua     # GET/POST/DELETE /api/favorites
            ├── api_match_notes.lua   # GET/POST /api/match-notes
            ├── api_goals.lua         # GET/POST/PUT/DELETE /api/goals
            ├── api_overlay.lua       # GET /overlay/{puuid} — OBS Browser Source
            ├── api_tracked_players.lua  # GET /api/tracked-players
            ├── api_leaderboard.lua   # GET /api/leaderboard — топ игроки сервера
            ├── api_clash.lua         # GET /api/clash — турниры Clash
            ├── api_health.lua        # GET /health — healthcheck
            ├── api_admin_players.lua # GET/POST/DELETE /api/admin/players
            ├── api_notification_prefs.lua # GET/PUT /api/notification-prefs
            ├── api_multi_search.lua  # GET /api/multi-search — параллельный поиск
            ├── api_live_briefing.lua # GET /api/live-game/{puuid}/briefing
            ├── api_records.lua       # GET /api/player/{puuid}/records
            ├── api_match_recap.lua   # GET /api/match/{matchId}/recap
            └── api_profile_link.lua  # GET /p/{slug} — shareable links
```

---

## Архитектура

### Процессная модель (Actor Model)

Шесть сервисов работают как отдельные процессы и общаются через шину событий (`"league_client"` канал):

```
┌─ Supervisor (process.service, auto_start) ─────────────────────┐
│  registry.find({meta.type: "player"}) → обнаруживает игроков   │
│  process.spawn_monitored("app.lc:fetcher") → запускает фетчер  │
│  Рестартует упавшие фетчеры (let-it-crash)                     │
└────────────────────────┬───────────────────────────────────────┘
                         │ spawn per player
                         ▼
┌─ Fetcher (per player, adaptive interval) ─────────────────────┐
│  Full fetch: account → summoner → ranked → mastery → matches  │
│  Quick poll: ranked + active_game (каждые 2 мин)              │
│  Adaptive interval: <30m→5m, >24h→1h, иначе→configured       │
│  events.send("league_client", "player.data_fetched", data)    │
└────────────────────────┬──────────────────────────────────────┘
                         │ events: data_fetched, fetch.failed
                         ▼
┌─ Data Manager (process.service) ──────────────────────────────┐
│  Подписка на "league_client"                                  │
│  Сохраняет данные в SQLite                                    │
│  Детектит изменения рангов → "player.rank_changed"            │
│  Обнаруживает новые матчи → "player.match_new"               │
│  Детектит вход в игру → "player.game_started"                 │
│  Проверяет достижение целей → "player.goal_achieved"          │
└──────┬──────────┬──────────┬──────────┬───────────────────────┘
       │          │          │          │
       ▼          ▼          ▼          ▼
┌─ Discord ─┐ ┌─ Telegram ─┐ ┌─ Weekly ──┐ ┌─ Dashboard ──────┐
│  Webhook   │ │  Bot API   │ │  Digest   │ │  WebSocket →     │
│  + Retry   │ │  Ранги,    │ │  Вс 9:00  │ │  клиент          │
│  Queue     │ │  матчи,    │ │  UTC      │ │  (real-time)     │
│  Per-player│ │  игры,     │ │  Итоги    │ │  Снапшот 30 сек  │
│  webhooks  │ │  голы      │ │  недели   │ │                  │
└────────────┘ └────────────┘ └───────────┘ └──────────────────┘
```

### Шина событий

| Событие | Отправитель | Подписчики | Данные |
|---------|------------|------------|--------|
| `player.data_fetched` | Fetcher | Data Manager, Session | summoner, ranked, mastery, matches, mastery_score |
| `player.rank_changed` | Data Manager | Discord, Telegram, Session | old_rank, new_rank, lp_diff |
| `player.match_new` | Data Manager | Discord, Telegram, Session | match data, lp_diff |
| `player.game_started` | Data Manager | Discord, Telegram, Session | game_id, champion |
| `player.goal_achieved` | Data Manager | Discord, Telegram, Session | goal details |
| `fetch.failed` | Fetcher | Session | error details |

Все события включают: `player_id`, `player_name`, `puuid`, `game_name`, `tag_line`, `platform`, `region`, `discord_notify`, `discord_webhook_url`.

### HTTP маршруты

| Метод | Путь | Обработчик | Описание |
|-------|------|-----------|----------|
| GET | `/` | page.lua | Рендер дашборда (+ HTTP Basic Auth) |
| GET | `/ws/updates` | ws_connect.lua | WebSocket upgrade |
| GET | `/health` | api_health.lua | Healthcheck (статус БД) |
| GET | `/overlay/{puuid}` | api_overlay.lua | OBS Browser Source оверлей |
| GET | `/api/search` | api_search.lua | Поиск игрока (name, tag, platform) |
| GET | `/api/player/{puuid}` | api_player.lua | Профиль из кэша |
| GET | `/api/player/{puuid}/stats` | api_player_stats.lua | Расширенная статистика |
| GET | `/api/recent-searches` | api_recent_searches.lua | Последние поиски |
| GET | `/api/rotations` | api_rotations.lua | Ротация чемпионов |
| GET | `/api/status` | api_status.lua | Статус серверов Riot |
| GET | `/api/match/{matchId}/timeline` | api_match_timeline.lua | Таймлайн матча |
| GET | `/api/tracked-players` | api_tracked_players.lua | Все отслеживаемые игроки |
| GET | `/api/leaderboard` | api_leaderboard.lua | Топ игроки сервера |
| GET | `/api/clash` | api_clash.lua | Турниры Clash |
| GET/POST/DELETE | `/api/favorites` | api_favorites.lua | Избранные игроки |
| GET/POST | `/api/match-notes` | api_match_notes.lua | Заметки к матчам |
| GET/POST/PUT/DELETE | `/api/goals` | api_goals.lua | Цели игрока |
| GET/PUT | `/api/notification-prefs` | api_notification_prefs.lua | Настройки уведомлений |
| GET/POST/DELETE | `/api/admin/players` | api_admin_players.lua | Управление отслеживаемыми игроками |
| GET | `/api/multi-search` | api_multi_search.lua | Параллельный поиск до 10 игроков |
| GET | `/api/live-game/{puuid}/briefing` | api_live_briefing.lua | Pre-game анализ оппонентов |
| GET | `/api/player/{puuid}/records` | api_records.lua | Личные рекорды игрока |
| GET | `/api/match/{matchId}/recap` | api_match_recap.lua | Текстовый рекап матча |
| GET | `/p/{slug}` | api_profile_link.lua | Redirect на профиль (shareable link) |
| GET | `/api/champions` | api_champion_stats.lua | Глобальная статистика чемпионов |
| GET | `/api/player/{puuid}/matchups` | api_champion_matchups.lua | Матчапы по чемпионам |
| GET | `/api/champion/{name}/builds` | api_champion_builds.lua | Руны и спеллы для чемпиона |

---

## Реестр Wippy (_index.yaml)

### Корневой реестр (src/_index.yaml, namespace: app.lc)

**Инфраструктура:**
- `db` (db.sql.sqlite) — SQLite база `./data/league.db`, auto_start
- `processes` (process.host) — 16 workers, auto_start
- `gateway` (http.service) — HTTP на порту :80, auto_start
- `router_http` (http.router) — роутер с prefix `/`

**Окружение (8 переменных):**
- `file_env` (env.storage.file) — `.env` файл
- `riot_api_key`, `riot_platform`, `riot_region` — Riot API
- `discord_webhook_url` — глобальный Discord вебхук
- `telegram_bot_token`, `telegram_chat_id` — Telegram бот
- `dashboard_password` — HTTP Basic Auth для дашборда

**Riot API функции** (function.lua, source: api/riot_api.lua, 17 методов):
- `riot_api_get_account`, `riot_api_get_summoner`, `riot_api_get_ranked`, `riot_api_get_mastery`
- `riot_api_get_matches`, `riot_api_get_match`, `riot_api_get_challenges`
- `riot_api_get_active_game`, `riot_api_get_champion_rotations`, `riot_api_get_status`
- `riot_api_get_match_timeline`, `riot_api_get_mastery_score`
- `riot_api_get_clash_tournaments`, `riot_api_get_clash_players`
- `riot_api_get_challenger_league`, `riot_api_get_grandmaster_league`, `riot_api_get_master_league`

**Data Dragon функции** (function.lua, source: api/data_dragon.lua):
- `ddragon_get_items`, `ddragon_get_runes`, `ddragon_get_version`, `ddragon_get_champions`

**Процессные сервисы** (process.service, auto_start, auto_restart):
- `supervisor` — depends_on: db
- `data_manager` — depends_on: db
- `discord_notifier`
- `telegram_notifier`
- `weekly_digest`

**Отслеживаемые игроки** (registry.entry, meta.type: "player"):
```yaml
- name: player_grishka
  kind: registry.entry
  meta:
    type: player
    game_name: Гришка Big Шишка
    tag_line: GiBi
    platform: RU
    region: EUROPE
    fetch_interval: "10m"
    ranked_poll_interval: "2m"
    discord_notify: true
```

Динамическое добавление игроков: `POST /api/admin/players`.

### Контракт player_storage (src/lib/_index.yaml, namespace: app.lc.lib)

**contract.definition** `players` — описание всех 68 методов хранилища

**contract.binding** `player_storage` — связывает все функции с контрактом

**Использование в коде:**
```lua
local contract = require("contract")
local storage, err = contract.open("app.lc.lib:player_storage")
storage:get_player({puuid = "..."})
```

**ВАЖНО:** Все функции контракта ОБЯЗАНЫ возвращать Lua таблицу (`{}`), а не примитивные типы.

---

## База данных SQLite

### Таблицы (20 штук)

#### players
| Колонка | Тип | Описание |
|---------|-----|----------|
| puuid | TEXT PK | Уникальный ID Riot |
| game_name | TEXT | Игровое имя |
| tag_line | TEXT | Тег (#GiBi) |
| summoner_id | TEXT | ID саммонера |
| summoner_level | INTEGER | Уровень |
| profile_icon_id | INTEGER | ID иконки |
| revision_date | INTEGER | Дата последнего обновления |
| platform | TEXT | Платформа (EUW1, RU, etc.) |
| region | TEXT | Регион (EUROPE, etc.) |
| total_mastery_score | INTEGER | Общие очки мастерства |
| updated_at | TEXT | Время обновления записи |

#### player_ranked
| Колонка | Тип | Описание |
|---------|-----|----------|
| id | INTEGER PK | Auto-increment |
| puuid | TEXT | FK → players |
| queue_type | TEXT | RANKED_SOLO_5x5, RANKED_FLEX_SR |
| tier | TEXT | IRON..CHALLENGER |
| rank | TEXT | I, II, III, IV |
| league_points | INTEGER | LP |
| wins, losses | INTEGER | W/L |
| hot_streak | INTEGER | Серия побед |
| veteran, fresh_blood | INTEGER | Флаги |
| updated_at | TEXT | |
| **UNIQUE** | | (puuid, queue_type) |

#### player_mastery
| Колонка | Тип | Описание |
|---------|-----|----------|
| id | INTEGER PK | |
| puuid | TEXT | FK → players |
| champion_id | INTEGER | ID чемпиона |
| champion_level | INTEGER | Уровень мастерства |
| champion_points | INTEGER | Очки мастерства |
| updated_at | TEXT | |
| **UNIQUE** | | (puuid, champion_id) |

#### matches (~40 колонок)
Основные: `match_id` (PK), `puuid`, `champion_id`, `champion_name`, `kills`, `deaths`, `assists`, `cs`, `vision_score`, `total_damage`, `gold_earned`, `win`, `game_duration`, `game_mode`, `queue_id`, `position`, `items` (JSON), `game_creation`, `summoner1`, `summoner2`, `lp_diff`

Расширенные: `double_kills`, `triple_kills`, `quadra_kills`, `penta_kills`, `physical_damage`, `magic_damage`, `true_damage`, `damage_taken`, `wards_placed`, `wards_killed`, `control_wards`, `kill_participation`, `damage_share`, `gold_per_min`, `damage_per_min`, `perks_keystone`, `perks_primary_style`, `perks_sub_style`, `champ_level`, `gold_spent`, `game_ended_surrender`, `first_blood`, `solo_kills`, `turret_plates`, `dragon_takedowns`, `baron_takedowns`, `rift_herald_takedowns`, `vision_per_min`, `lane_minions_first10`, `max_cs_advantage`, `max_level_lead`, `turret_takedowns`, `inhibitor_takedowns`

Индекс: `(puuid, game_creation DESC)`

#### match_participants
Та же структура что и `matches`, плюс `team_id`, `summoner_name`, `tag_line`. Индексы: `(match_id)`, `(puuid)`. UNIQUE: `(match_id, puuid)`.

#### player_challenges
| puuid (PK) | level | current_points | max_points | percentile | total_mastery_score | updated_at |

#### recent_searches
| id (PK) | puuid (UNIQUE) | game_name | tag_line | summoner_level | profile_icon_id | platform | searched_at |

#### ranked_history
| id (PK) | puuid | queue_type | recorded_at | tier | rank | league_points | wins | losses |
Индекс: `(puuid, queue_type, recorded_at DESC)`

#### winrate_history
| puuid | date | wins | losses | games | winrate |

#### duo_partners
| puuid | ally_puuid | games | wins |

#### ddragon_cache
| cache_key (PK) | data (JSON) | version | updated_at |
TTL: 24 часа

#### favorites
| id (PK) | puuid (UNIQUE) | game_name | tag_line | platform | region | note | created_at |

#### match_notes
| match_id + puuid (PK) | note | updated_at |

#### player_goals
| id (PK) | puuid | goal_type | target_value | current_value | completed (0/1) | created_at | completed_at |

#### notification_queue
| id (PK) | webhook_url | payload (JSON) | attempts | next_retry | success |

#### notification_prefs
| puuid (PK) | notify_rank_changes | notify_matches | notify_games | notify_goals |

#### managed_players
| id (PK) | puuid | game_name | tag_line | platform | region | active | added_by | created_at |

#### api_metrics
| id (PK) | endpoint | status_code | response_time_ms | cached | created_at |

#### player_records
| puuid + record_type (UNIQUE) | value | match_id | champion_name | achieved_at |

#### match_timeline_stats
| match_id + puuid (UNIQUE) | cs_at_10 | cs_at_15 | gold_at_10 | gold_at_15 | gold_diff_at_10 | gold_diff_at_15 | xp_diff_at_10 | first_blood_time |

---

## Riot API интеграция

### Маршрутизация запросов

- **Platform** (`{platform}.api.riotgames.com`): Summoner, League, Mastery, Champion, Spectator, Challenges, Status, Clash
- **Regional** (`{region}.api.riotgames.com`): Account, Match

### Поддерживаемые платформы и регионы

| Платформы | Регион |
|-----------|--------|
| BR1, LA1, LA2, NA1, OC1 | AMERICAS |
| EUW1, EUN1, RU, TR1, ME1 | EUROPE |
| KR, JP1 | ASIA |
| PH2, SG2, TH2, TW2, VN2 | SEA |

### API методы (riot_api.lua, 17 методов)

| Метод | Endpoint | Маршрутизация |
|-------|----------|---------------|
| get_account | `/riot/account/v1/accounts/by-riot-id/{name}/{tag}` | Regional |
| get_summoner | `/lol/summoner/v4/summoners/by-puuid/{puuid}` | Platform |
| get_ranked | `/lol/league/v4/entries/by-puuid/{puuid}` | Platform |
| get_mastery | `/lol/champion-mastery/v4/champion-masteries/by-puuid/{puuid}/top` | Platform |
| get_mastery_score | `/lol/champion-mastery/v4/scores/by-puuid/{puuid}` | Platform |
| get_matches | `/lol/match/v5/matches/by-puuid/{puuid}/ids` | Regional |
| get_match | `/lol/match/v5/matches/{matchId}` | Regional |
| get_match_timeline | `/lol/match/v5/matches/{matchId}/timeline` | Regional |
| get_challenges | `/lol/challenges/v1/player-data/{puuid}` | Platform |
| get_active_game | `/lol/spectator/v5/active-games/by-summoner/{puuid}` | Platform |
| get_champion_rotations | `/lol/platform/v3/champion-rotations` | Platform |
| get_status | `/lol/status/v4/platform-data` | Platform |
| get_clash_tournaments | `/lol/clash/v1/tournaments` | Platform |
| get_clash_players | `/lol/clash/v1/players/by-puuid/{puuid}` | Platform |
| get_challenger_league | `/lol/league/v4/challengerleagues/by-queue/{queue}` | Platform |
| get_grandmaster_league | `/lol/league/v4/grandmasterleagues/by-queue/{queue}` | Platform |
| get_master_league | `/lol/league/v4/masterleagues/by-queue/{queue}` | Platform |

### Data Dragon (без API ключа)

| Метод | URL |
|-------|-----|
| get_latest_version | `ddragon.leagueoflegends.com/api/versions.json` |
| get_champions | `ddragon.leagueoflegends.com/cdn/{ver}/data/{lang}/champion.json` |
| get_items | `ddragon.leagueoflegends.com/cdn/{ver}/data/{lang}/item.json` |
| get_runes | `ddragon.leagueoflegends.com/cdn/{ver}/data/{lang}/runesReforged.json` |

---

## Главный API: GET /api/search (api_search.lua)

Самый большой файл проекта (~1577 строк). Выполняет полный поиск игрока и вычисляет десятки метрик.

### Параметры запроса

| Параметр | Описание | Обязательный |
|----------|----------|-------------|
| name | Игровое имя | Да |
| tag | Тег (без #) | Да |
| platform | Платформа (EUW1, RU, etc.) | Нет (default: env) |
| region | Регион | Нет (auto из platform) |

### Что возвращает

**Основные данные:**
- `account` — {puuid, game_name, tag_line}
- `summoner` — {level, profile_icon_id, profile_icon_url}
- `ranked` — массив с данными по очередям (tier, rank, LP, W/L, winrate)
- `mastery` — топ-20 чемпионов с именами и иконками
- `matches` — последние 20 матчей (из кэша + свежие с API)
- `challenges` — челленджи игрока
- `live_game` — текущая игра (если в игре), с рангами всех участников

**Статистика (stats):**
- Базовая: games, wins, losses, winrate, avg KDA, avg CS/min, avg damage, avg gold, avg vision
- Киллы: penta/quadra/triple, total solo kills
- Damage breakdown: physical %, magic %, true %
- Win/Loss split: отдельные метрики для побед и поражений
- Champion pool: unique_champions, pool_depth (One-Trick/Specialist/Versatile), pool_top_pct
- Recent form: последние 5 игр
- Game length preference: Early Game/Balanced/Late Game
- Snowball index: CS advantage + level lead

**Аналитика по чемпионам:**
- `top_champions` — чемпионы с играми, WR, средними KDA, CS, damage
- `position_distribution` — распределение по ролям (Top/Jungle/Mid/ADC/Support)
- Keystones per champion — руны с WR

**Матчап-анализ:**
- `enemy_matchups` — WR против конкретных чемпионов (мин. 2 игры)
- `lane_matchups` — лейновые оппоненты с детальной статистикой
- `ally_synergy` — WR с определёнными тиммейтами

**Предметы:**
- `common_items` — топ-15 предметов по частоте, с pick rate и WR

**Вычисляемые фичи:**
- `build_recommendations` — лучшие комбинации предметов по чемпионам
- `patch_impact` — изменение WR по неделям (детект бафов/нерфов)
- `champion_recommendations` — рекомендации чемпионов по синергии и контрпикам
- `rank_percentile` — процентиль ранга среди всех игроков
- `is_favorite` — в избранном ли игрок
- `match_notes` — заметки к матчам
- `goals` — цели игрока

**DDragon данные:**
- `dd_version`, `items_data`, `runes_data` — для отображения иконок в UI

### Стратегия кэширования

1. Проверяет `storage:check_existing_matches()` — какие матчи уже в БД
2. Отдаёт кэшированные матчи из БД
3. Запрашивает только новые матчи через API (с задержкой 200мс между запросами)
4. DDragon кэшируется на 24 часа в таблице `ddragon_cache`

---

## Расширенная статистика: GET /api/player/{puuid}/stats

Возвращает аналитические данные, не входящие в основной поиск:

| Поле | Описание |
|------|----------|
| `duo_partners` | Частые тиммейты (puuid, имя, игры, победы) |
| `winrate_history` | История WR по дням (30 дней) |
| `lp_history` | LP снапшоты для Solo/Duo и Flex |
| `today_stats` | Игры/победы/поражения за сегодня |
| `peak_lp` | Лучший ранг за всё время (per queue) |
| `form_trend` | Дельта WR: последние 7 дней vs предыдущие 7 |
| `daily_tip` | Контекстная подсказка на основе статистики |
| `lp_velocity` | LP в день, дней до следующего дивизиона |
| `personal_enemies` | Чемпионы-враги с худшим WR |
| `records` | Личные рекорды (10 типов) |
| `season_history` | История рангов по сплитам |

---

## Дашборд UI (dashboard.jet)

Один большой Jet-шаблон (~3000+ строк), содержащий HTML + CSS + JavaScript.

### Основные секции UI

1. **Заголовок** — логотип, поиск (имя + тег), выбор региона (16 серверов)
2. **Избранные** — сетка избранных игроков с рангами
3. **Профиль игрока** — иконка, имя, уровень, ранг, процентиль, кнопки (избранное, экспорт, CSV, уведомления)
4. **Ранги** — Solo/Duo, Flex и ARAM с прогресс-баром LP, бейджами (hot streak, veteran, fresh blood)
5. **Цели** — форма добавления целей (ранг), список с прогрессом, автодетект достижения
6. **Матчи** — список матчей с детальной статистикой, фильтры по очереди, заметки к матчам
7. **Статистика** — вкладки:
   - **Overview** — WR, KDA, CS/min, damage, vision, wards, рекорды, pool depth, playstyle, streaks, multi-kills
   - **Champions** — карточки чемпионов с WR, позицией, keystone, damage composition
   - **Roles** — donut chart распределения по ролям
   - **Advanced** — radar chart, game length, objectives, early game, snowball, win vs loss, summoner spells
   - **Matchups** — WR против врагов, lane opponents
   - **Items** — частые предметы с WR и pick rate
   - **Synergy** — лучшие/худшие союзные чемпионы
   - **Builds** — рекомендуемые сборки по чемпионам
   - **Insights** — тренды, рекомендации чемпионов
   - **Compare** — сравнение нескольких игроков
8. **Расширенная статистика** — дуо-партнёры, WR история, LP velocity, personal enemies, LP chart
9. **Live Game** — текущая игра с рангами всех участников
10. **Ротация** — бесплатные чемпионы
11. **Статус сервера** — инциденты и обслуживание

### SVG визуализации

- **Kill Map** — карта убийств на мини-карте Summoner's Rift
- **Gold Difference Graph** — график разницы золота по командам
- **LP Line Chart** — линейный график LP за время
- **Win Rate History Chart** — график WR за 30 дней
- **Radar Chart** — многоосевая диаграмма навыков

### JavaScript функции

| Функция | Описание |
|---------|----------|
| `doSearch()` | Поиск игрока, обновляет URL state (?player=...&platform=...) |
| `loadFavorites()` | Загрузка списка избранных |
| `toggleFavorite()` | Добавить/удалить из избранного |
| `renderGoals()` | Отображение целей с кнопками complete/delete |
| `addGoal()` | Создание новой цели |
| `saveMatchNote()` | Сохранение заметки к матчу |
| `addComparePlayer()` | Добавление игрока в сравнение |
| `renderCompare()` | Рендер таблицы сравнения |
| `toggleNotifications()` | Browser Notification API |
| `exportProfile()` | Экспорт профиля как .txt файл |
| `exportCSV()` | Экспорт матчей как .csv файл |
| `renderStats()` | Все вкладки статистики |
| `handleWsMessage()` | Обработка WebSocket сообщений |
| `initTheme()` | Тема: dark/light + prefers-color-scheme |

### Горячие клавиши

Клавиатурные сокращения для быстрой навигации по дашборду.

### Персистентность (localStorage)

- Выбранный регион
- Состояние уведомлений (включены/выключены)
- Тема (dark/light)

### Адаптивный дизайн

- Breakpoints: 768px (планшет), 480px (мобильный)
- Enhanced mobile CSS для всех секций

---

## OBS Overlay

**GET /overlay/{puuid}** — прозрачный виджет 200×320px для OBS Browser Source.

Показывает:
- Текущий ранг с иконкой тира
- Сегодняшние W/L
- Последние 5 игр (зелёные/красные точки)
- Auto-refresh

---

## WebSocket (real-time обновления)

### Подключение

1. Клиент подключается к `ws://localhost:80/ws/updates`
2. `ws_connect.lua` спавнит `session_process`
3. Middleware relay перенаправляет сообщения в сессию

### Протокол сообщений (JSON)

**Сервер → Клиент:**
```json
{"type": "player_update", "data": {...}}
{"type": "rank_change", "data": {...}}
{"type": "new_match", "data": {...}}
{"type": "game_started", "data": {...}}
{"type": "goal_achieved", "data": {...}}
{"type": "fetch_failed", "data": {...}}
{"type": "snapshot", "players": [...]}
{"type": "welcome", "message": "..."}
```

**Клиент → Сервер:**
```json
{"type": "request_snapshot"}
```

### Обновления

- Real-time события от фетчеров (ранги, матчи, игры, цели, ошибки)
- Полный снапшот всех игроков каждые 30 секунд

---

## Система уведомлений

### Discord

**Конфигурация:**
- Глобальный: `DISCORD_WEBHOOK_URL` в `.env`
- Per-player: `discord_webhook_url` в мета-данных игрока (переопределяет глобальный)
- Флаг `discord_notify: true` в мета-данных игрока

**Типы уведомлений:**
1. **Rank Change** — embed с цветом (зелёный повышение / красный понижение), LP diff, WR
2. **New Match** — embed с KDA, CS, damage, позиция, длительность, LP change, ссылка на op.gg
3. **Game Started** — игрок зашёл в матч
4. **Goal Achieved** — игрок достиг цели по рангу

**Retry Queue:** Неудачные отправки помещаются в очередь с экспоненциальным retry.

### Telegram

**Конфигурация:**
- `TELEGRAM_BOT_TOKEN` — токен бота
- `TELEGRAM_CHAT_ID` — ID чата для отправки

Подписывается на те же события, что и Discord. Форматирует сообщения в Telegram Markdown.

### Weekly Digest

Каждое воскресенье в 9:00 UTC отправляет в Discord сводку за неделю:
- Итоги по каждому отслеживаемому игроку
- Изменения ранга за неделю
- Слабые стороны и рекомендации

### Notification Preferences

Per-player настройки через `/api/notification-prefs`:
- `notify_rank_changes` — уведомления о смене ранга
- `notify_matches` — уведомления о новых матчах
- `notify_games` — уведомления о входе в игру
- `notify_goals` — уведомления о достижении целей

---

## Переменные окружения (.env)

| Переменная | Описание | Обязательна |
|-----------|----------|-------------|
| RIOT_API_KEY | Ключ API Riot Games | Да |
| RIOT_PLATFORM | Платформа по умолчанию (EUW1, NA1, KR, RU...) | Да |
| RIOT_REGION | Регион по умолчанию (EUROPE, AMERICAS, ASIA, SEA) | Да |
| DISCORD_WEBHOOK_URL | URL глобального вебхука Discord | Нет |
| TELEGRAM_BOT_TOKEN | Токен Telegram бота | Нет |
| TELEGRAM_CHAT_ID | ID чата Telegram | Нет |
| DASHBOARD_PASSWORD | Пароль HTTP Basic Auth для дашборда | Нет |

---

## Как добавить отслеживаемого игрока

### Способ 1: Через реестр (статический)

Добавить в `src/_index.yaml`:

```yaml
- name: player_faker
  kind: registry.entry
  meta:
    type: player
    game_name: Hide on bush
    tag_line: KR1
    platform: KR
    region: ASIA
    fetch_interval: "10m"
    ranked_poll_interval: "2m"
    discord_notify: true
    discord_webhook_url: "https://discord.com/api/webhooks/..."  # опционально
```

Перезапустить сервис — супервизор автоматически обнаружит и запустит фетчер.

### Способ 2: Через API (динамический)

```bash
# Добавить
curl -X POST http://localhost/api/admin/players \
  -H "Content-Type: application/json" \
  -d '{"game_name":"Faker","tag_line":"KR1","platform":"KR","region":"ASIA"}'

# Список
curl http://localhost/api/admin/players

# Удалить
curl -X DELETE http://localhost/api/admin/players \
  -H "Content-Type: application/json" \
  -d '{"puuid":"..."}'
```

---

## Важные паттерны для разработки

### Контрактная система

**Все функции контракта обязаны возвращать Lua-таблицу.** Нельзя возвращать raw boolean, string или number.

```lua
-- ПРАВИЛЬНО
return {is_favorite = true}
return {goals = rows or {}}
return {ok = true}

-- НЕПРАВИЛЬНО (сломает контракт)
return true
return rows
```

### Регистрация новой функции в контракте

1. **Написать функцию** в `src/lib/players.lua` и экспортировать в return-таблице
2. **Добавить метод в contract.definition** в `src/lib/_index.yaml` (секция `players`, массив `methods`)
3. **Добавить function.lua запись** — отдельная entry с source, method, modules
4. **Добавить привязку** в `contract.binding` `player_storage` (секция `methods`)

### Миграция схемы БД

Используется паттерн `pcall` для ALTER TABLE:

```lua
pcall(function() db:execute("ALTER TABLE matches ADD COLUMN new_col TEXT DEFAULT ''") end)
```

### Кэширование DDragon

```lua
local cached = storage:get_ddragon_cache({key = "champions", ttl_hours = 24})
if cached and cached.data then
    -- использовать кэш
else
    -- запросить API и сохранить
    storage:save_ddragon_cache({key = "champions", data = json_string, version = ver})
end
```

### Добавление нового API endpoint

1. Написать handler в `src/dashboard/handlers/api_xxx.lua`
2. Зарегистрировать в `src/_index.yaml`:
   ```yaml
   - name: api_xxx
     kind: function.lua
     source: file://dashboard/handlers/api_xxx.lua
     method: handler
     modules: [http, json, contract]

   - name: api_xxx_endpoint
     kind: http.endpoint
     meta:
       router: app.lc:router_http
     method: GET
     path: /api/xxx
     func: app.lc:api_xxx
   ```

---

## Запуск и диагностика

```bash
# Запуск
wippy run

# Линтер
wippy lint
wippy lint --level hint
wippy lint --ns app.lc

# Реестр
wippy registry list
wippy registry list --kind "function.lua"
wippy registry show app.lc:player_storage
```

Сервер стартует на `http://localhost:80`. Все сервисы auto_start.

---

## Реализованные фичи

### Level 1 — Core (6 фич)
1. Поиск игрока по Riot ID
2. Профиль (уровень, иконка)
3. Ранги (Solo/Flex/ARAM)
4. Топ чемпионы по мастерству
5. Последние матчи с KDA
6. WebSocket real-time

### Level 2 — Enhanced (6 фич)
7. Детальная статистика матчей (damage, gold, vision, wards, solo kills, objectives)
8. Статистика по чемпионам (WR, avg KDA per champ, keystones, damage composition)
9. Матчапы (enemy matchups, lane matchups)
10. Дуо-партнёры (frequent teammates)
11. Недавние поиски
12. Ротация бесплатных чемпионов

### Level 3 — Advanced Viz (4 фичи)
13. Kill Map (SVG мини-карта)
14. Gold Difference Graph (SVG)
15. LP Line Chart (SVG)
16. Team Comp Analysis (damage composition)

### Level 4 — Features (8 фич)
17. Multi-Region поддержка (16 серверов)
18. Избранные игроки
19. Compare Mode (сравнение игроков)
20. Build Recommendations (лучшие сборки)
21. Rank Percentile
22. Push Notifications (Browser API)
23. Mobile Layout (адаптивный, enhanced)
24. Export Profile (.txt + .csv)

### Level 5 — Analytics (4 фичи)
25. Patch Impact Tracker (WR changes by week)
26. Goal Tracking (цели игрока с автодетектом)
27. Match Notes (заметки к матчам)
28. Champion Recommendations (синергия + контрпики)

### Brainstorm 2 — Extended Features (20 фич)
29. Today Block — игры/победы/поражения за сегодня
30. Peak LP — лучший ранг за всё время
31. Form Trend — дельта WR (7 дней vs предыдущие 7)
32. Match URL в Discord — ссылка на op.gg
33. Total Mastery Score — общие очки мастерства
34. Dark/Light Mode — тема + prefers-color-scheme
35. Keyboard Shortcuts — горячие клавиши
36. In-Game Status — отслеживание входа в игру
37. Daily Tip — контекстная подсказка
38. Per-Player Discord Webhook — индивидуальные вебхуки
39. Notification Retry Queue — повторная отправка при ошибке
40. Weekly Digest — еженедельная сводка (вс 9:00 UTC)
41. Notification Preferences — настройки уведомлений per-player
42. Clash Tournaments — текущие турниры + команды
43. Server Leaderboard — Challenger/Grandmaster/Master
44. Telegram Notifier — параллельные уведомления в Telegram
45. Healthcheck — GET /health
46. Managed Tracked Players — динамическое добавление игроков через API
47. Enhanced Mobile CSS — улучшенная мобильная версия
48. Web Push — браузерные push-уведомления (частичная реализация)

### Brainstorm 3 — Quick Wins (10 фич)
49. LP Velocity — скорость набора LP, дней до следующего дивизиона
50. Personal Enemies — чемпионы-враги с худшим WR
51. OBS Overlay — прозрачный виджет для стриминга (`/overlay/{puuid}`)
52. URL State — поиск сохраняется в URL (?player=...&platform=...)
53. Auto Theme Detection — prefers-color-scheme из ОС
54. Adaptive Fetch Interval — <30m→5m, >24h→1h
55. Export CSV — экспорт матчей в CSV
56. HTTP Basic Auth — защита дашборда паролем
57. Tilt Detector — анализ формы vs общая статистика (клиент)
58. Tracked Players API — GET /api/tracked-players с ранг-данными

### Brainstorm 4 — Wave 3 (10 фич)
59. API Metrics Tracking — логирование всех вызовов Riot API (endpoint, status, response_time, cached)
60. Enhanced Healthcheck — API metrics summary, player freshness, stale alerts
61. Personal Records — личные рекорды (most kills, assists, cs, damage, gold, KDA, vision, cs/min, lowest deaths, penta)
62. Season History — история рангов по сплитам (Split 1/2/3)
63. Match Recap — текстовый рекап матча (KDA, CS, vision, multi-kills, damage share)
64. Performance Score — 0-100 скоринг матча (S+/S/A/B/C/D) с отображением в Discord
65. Multi-Search — одновременный поиск до 10 игроков (/api/multi-search)
66. Pre-Game Briefing — анализ слабостей/сильных сторон оппонентов в live game (/api/live-game/{puuid}/briefing)
67. Shareable Profile Links — GET /p/{Name}-{Tag}-{Platform} → redirect
68. Timeline Stats Schema — схема для хранения CS@10/15, Gold@10/15, Gold diff, XP diff

### Wave 4 — SQL Analytics (10 фич)
69. Match History Filtering — фильтрация матчей по чемпиону, роли, очереди, результату
70. LP Per Game — отображение +/-LP на каждом ранговом матче
71. Role Distribution — распределение игр и WR по ролям
72. Damage Composition — профиль урона (physical/magic/true %)
73. Game Duration Analysis — WR по бакетам длительности (<20m, 20-25m, 25-30m, 30-35m, 35+m)
74. Best Time to Play — WR по часам дня и дням недели
75. Surrender & Remake Stats — процент сдач, ремейков, first blood rate
76. Multi-Queue Breakdown — статистика по типам очередей
77. Summoner Spell Analysis — WR по комбинациям заклинаний
78. Server-side Match Filtering — API поддержка ?champion=&position=&queue=&win=

### Wave 5 — Advanced Analytics (6 фич)
79. Champion Matchups API — GET /api/player/{puuid}/matchups?champion=&position=
80. Champion Global Stats — GET /api/champions?queue=420&position=MID (агрегат из всех матчей)
81. Vision Trend — тренд вижн скора по последним матчам (бар-чарт)
82. Peer Comparison Percentiles — перцентили CS, Vision, KDA, Damage, KP vs другие игроки
83. Early Game Stats — avg CS@10, Gold@10, Gold Diff@10, XP Diff@10 из timeline данных
84. Comeback/Throw Detection — анализ камбэков и бросков (уже был в UI, теперь усилен)

### Wave 6 — Timeline Deep Integration (5 фич)
85. Timeline Auto-Parse — автоматический парсинг timeline для каждого нового матча (CS@10/15, Gold@10/15, diffs)
86. Champion Builds API — GET /api/champion/{name}/builds (руны + спеллы, агрегат из матчей)
87. Objective Control Stats — avg dragons/barons/heralds/turrets/plates + first blood conversion
88. Early Game Stats UI — визуализация CS@10, Gold@10, Gold Diff@10, XP Diff@10
89. Vision Trend UI — бар-чарт vision/min по последним матчам + avg wards/CW

**Итого: 89 реализованных фич.**
