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
  Keys don't expire on their own — changing the password issues a new one,
  which is also how you sign other devices out.
- **Health ingest** checks the same key on its own, because the iOS Shortcut
  posts from outside the LAN and never logs in.

Passwords are PBKDF2-SHA256, and the login endpoint allows ten failures per
client IP per fifteen minutes before returning 429. Setting a password —
whether by the user via `PUT /api/me/password` or by an admin resetting it —
always issues a fresh API key, because the API authenticates on the key and
never rechecks the password; without that, a device you're trying to lock out
would keep working. The self-service endpoint requires the current password
and answers a wrong one with 403 rather than 401, so a typo isn't mistaken for
an expired session. `WithAPIKey` resolves the
caller; `WithAdmin` additionally requires the admin role.

## Accounts

Three ways in, depending on how open you want the server to be:

- **Seeded admin** — created on first boot from `AUTH_USER` / `AUTH_PASS`.
- **Admin-created** — Settings → Admin → Manage users, in the app.
- **Self-service sign-up** — off unless you set `SIGNUP_INVITE_CODE`. With it
  set, `POST /api/auth/signup` accepts anyone presenting that code and the app
  shows a "Create an account" button; the endpoint shares the login rate
  limiter, and the code is compared in constant time. Sign-ups are always role
  `user` — admins are promoted by other admins, never self-assigned.

Anyone can close their own account with `DELETE /api/me`, which cascades
through every table. The last remaining admin is refused, so a server can't be
left with nobody able to manage it.

## Who owns what

Every table holding a person's data carries a `user_id`, and every query is
scoped to the caller — two accounts on one server never see each other's
workouts, weigh-ins, meals, or Apple Health days. Reaching for another user's
row by id returns 404, not 403, so ids don't leak either. Deleting an account
cascades to its data.

Two things are deliberately shared: the **exercise library** and its
**body-part tags**. They're a catalogue rather than personal data, and
splitting them would mean everyone retyping "Bench Press". Set counts and PRs
shown against an exercise are still per-user. An exercise can't be deleted
while *anyone* has sets logged against it.

The **scheduled syncs are the exception**: LA Fitness and Healthifyme
credentials come from the environment, not from each user, so exactly one
account can own them — the admin named by `AUTH_USER`. Everyone else logs by
hand and pushes Apple Health with their own API key, both of which are already
per-user. Per-user integration credentials would need somewhere safe to keep
them, which this doesn't have yet.

## Demo data

A brand-new account opens on empty screens, which is fine for you and
unhelpful for anyone evaluating the app. `cmd/seed-demo` fills one account with
plausible history — a four-day split, a slow cut with realistic day-to-day
weight noise, sleep stages, macros and gym check-ins:

```sh
go run ./cmd/seed-demo -db data.db -email demo@example.com -password secret -days 120
```

It creates the account if it's missing, wipes and regenerates on every run, and
is deterministic, so re-running reproduces the same history. It only ever
touches that user's rows, reads the shared exercise library without writing to
it, and leaves every other account alone.

## Migrations

`PRAGMA user_version` tracks the schema; `migrate()` in `db/db.go` walks it
forward on boot. Version 2 added `user_id` to every data table and handed
existing rows to the first admin — on a single-person install, the person whose
data it always was. Migrations are idempotent, so a restart is a no-op.

## Routes

| Method | Path | |
|---|---|---|
| `POST` | `/api/auth/login` | email + password → user + API key |
| `POST` | `/api/auth/signup` | self-service sign-up; needs `SIGNUP_INVITE_CODE` |
| `GET` | `/api/health/ping` | liveness + whether sign-up is enabled, unauthenticated |
| `POST` | `/api/health/ingest` | Apple Health payload from the Shortcut |
| `GET` `PUT` | `/api/me` | profile (display name, date of birth, sex) |
| `PUT` | `/api/me/password` | change your own password; returns a fresh API key |
| `DELETE` | `/api/me` | close your own account, cascading to all its data |
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
