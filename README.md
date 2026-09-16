# pi-webpage

A self-hosted personal health dashboard that runs on a Raspberry Pi (or any
Linux box). It pulls gym check-ins and nutrition from third-party services,
accepts Apple Health data pushed from an iOS Shortcut, and lets you log lifts
and body measurements by hand — then puts the whole day on one calendar.

Two clients share one backend:

- **Web UI** — server-rendered [templ](https://templ.guide) + [htmx](https://htmx.org), dark terminal theme
- **iOS + watchOS app** — native SwiftUI, in [`ios/`](ios/) (see [ios/README.md](ios/README.md))

## What it tracks

| Area | Source |
|---|---|
| Gym check-ins | LA Fitness API (scheduled sync) |
| Nutrition — calories and macros | Healthifyme API (scheduled sync) |
| Steps, sleep stages, resting HR, active energy | Apple Health, pushed to `POST /api/health/ingest` |
| Workouts — exercises, sets, reps, weight | Logged in the app or web UI |
| Body — weight and caliper skinfolds | Logged in the app or web UI (Jackson-Pollock 3-site BF%) |

Analytics on top of that: a month/week calendar, lifting stats (PRs, estimated
1RM, weekly set volume by body part), and long-run weight/nutrition trends.

## Stack

- **Go 1.25**, standard-library `net/http` routing — no web framework
- **SQLite** via [modernc.org/sqlite](https://modernc.org/sqlite) (pure Go, so it cross-compiles to ARM with `CGO_ENABLED=0`)
- **templ** for typed HTML components, **htmx** + **hyperscript** for interactivity, **Chart.js** for graphs
- **robfig/cron** for the sync scheduler
- Auth: cookie sessions for the web UI, `X-Api-Key` for `/api/*`; passwords hashed with PBKDF2-SHA256

## Running it

```sh
cp .env.example .env   # then edit it
templ generate         # regenerate components/*_templ.go
go run .               # listens on :8080
```

The first boot seeds an admin account from `AUTH_USER` / `AUTH_PASS` if the
users table is empty; every setting is documented in [.env.example](.env.example).
Further accounts are created from **Settings → Admin → Manage users**.

`templ generate` needs the templ CLI:

```sh
go install github.com/a-h/templ/cmd/templ@v0.3.1020
```

### Deploying to a Pi

Cross-compile a single static binary (the templ views are compiled in, so
nothing else needs copying):

```sh
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o pi-webpage .
```

Copy it to the host along with your `.env`, then run it under systemd —
[`pi-monitor.service`](pi-monitor.service) is a starting point (adjust `User`
and the paths). [`Caddyfile`](Caddyfile) is an example reverse proxy that
exposes *only* the Apple Health ingest endpoint publicly and keeps the rest of
the API and UI on the LAN/VPN.

## Layout

```
main.go          route table — the quickest map of the app
handlers/        HTTP handlers: web pages (templ) and the JSON API (/api/*)
components/      templ views (*.templ; *_templ.go is generated — don't edit)
db/              SQLite schema and queries, one file per domain
sync/            LA Fitness + Healthifyme clients and the cron scheduler
ios/             SwiftUI app, watch app, and widget (XcodeGen project)
PLAN.md          design notes for the iOS app + the JSON API contract
```

## Notes

This is a personal project, published because the pieces may be useful to
someone building something similar. It is **not** hardened for use on the open
internet: keep it behind a VPN or LAN, as the example Caddyfile does. The
third-party syncs talk to undocumented endpoints and can break at any time.
