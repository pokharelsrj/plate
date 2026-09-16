# Plate — backend

A single Go binary: a JSON API over SQLite, plus two scheduled syncs. No
templates, no static assets, no web UI — [`../ui`](../ui) is the only client.

## Running it

```sh
cp .env.example .env
go run .            # :8080
```

Every setting is documented in [`.env.example`](.env.example). On first boot,
if the `users` table is empty, an admin is seeded from `AUTH_USER` /
`AUTH_PASS` (reusing `HEALTH_API_KEY` as its API key if set). After that,
accounts are managed from the app under **Settings → Admin → Manage users**.

## Deploying

Pure-Go SQLite, so it cross-compiles to a Pi with no toolchain fuss:

```sh
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o plate .
```

Copy the binary and your `.env` to the host and run it under systemd —
[`plate.service`](plate.service) is a starting point; adjust `User` and the
paths. [`Caddyfile`](Caddyfile) is an example reverse proxy that publishes
*only* the Apple Health ingest endpoint and 404s everything else, so the rest
of the API stays on your LAN or VPN.

## Auth

Two mechanisms, both `X-Api-Key`:

- **Per-user keys.** `POST /api/auth/login` trades email + password for the
  user's key; the app stores it in the Keychain and sends it on every request.
  Keys don't expire — rotate with `POST /api/me/rotate-key`.
- **Health ingest** checks the same key on its own, because the iOS Shortcut
  posts from outside the LAN and never logs in.

Passwords are PBKDF2-SHA256. `WithAPIKey` resolves the caller; `WithAdmin`
additionally requires the admin role.

## Routes

| Method | Path | |
|---|---|---|
| `POST` | `/api/auth/login` | email + password → user + API key |
| `GET` | `/api/health/ping` | liveness, unauthenticated |
| `POST` | `/api/health/ingest` | Apple Health payload from the Shortcut |
| `GET` `PUT` | `/api/me` | profile (display name, date of birth, sex) |
| `POST` | `/api/me/rotate-key` | issue a new API key |
| `GET` `POST` | `/api/admin/users` | list / create — admin only |
| `PUT` `DELETE` | `/api/admin/users/{id}` | update / delete — admin only |
| `POST` | `/api/admin/users/{id}/reset-password` | admin only |
| `GET` | `/api/today`, `/api/day?date=` | one day: gym, nutrition, health, body, workout |
| `GET` | `/api/calendar?view=month\|week&date=` | a grid of days + period averages |
| `GET` | `/api/workout?date=` | a session's sets, grouped by exercise |
| `POST` | `/api/workout/set` | log a set |
| `PUT` `DELETE` | `/api/workout/set/{id}` | edit / remove a set |
| `GET` | `/api/workout/stats?range=` | PRs, est. 1RM, progressions, weekly volume |
| `GET` `POST` | `/api/exercises` | the shared exercise library |
| `PUT` `DELETE` | `/api/exercises/{id}` | |
| `GET` `POST` | `/api/body-parts` | tags used to group exercises |
| `DELETE` | `/api/body-parts/{name}` | |
| `GET` `POST` | `/api/body` | weight + caliper history; posting recomputes BF% |
| `GET` | `/api/trends?range=` | weight, calories, steps, sleep over time |
| `GET` | `/api/sync` | last run and status per source |
| `POST` | `/api/sync/trigger` | run a sync now |

JSON is `snake_case` throughout. Anything unmatched 404s.

## Layout

```
main.go                 the route table — the fastest map of the whole thing
handlers/api_*.go       one file per resource
handlers/calendar.go    builds the month/week grid behind /api/calendar
handlers/bodyfat.go     Jackson-Pollock 3-site formula
handlers/health_ingest.go   the Apple Health endpoint
db/                     schema + queries, one file per domain
sync/                   LA Fitness and Healthifyme clients, and the cron
```

## Syncs

`sync/scheduler.go` registers each source with a backfill window and a daily
window. On boot, `MaybeInitialBackfill` fills history if the tables are empty;
after that the cron pulls the last few days so late-arriving data gets picked
up. Runs are recorded in `sync_runs` and surfaced at `GET /api/sync`.

Both sources are undocumented third-party endpoints. Expect them to break, and
expect the fix to be a small one.
