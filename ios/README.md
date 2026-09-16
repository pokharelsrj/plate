# Pi iOS app

Native SwiftUI client for the pi-webpage Go backend (see `../PLAN.md`).

## Requirements

- Xcode 15+ (iOS 17 SDK)
- A free or paid Apple developer account for device installs

## Open & run

```sh
open Pi.xcodeproj
```

1. Select the **Pi** target → Signing & Capabilities → pick your personal team.
2. Plug in your iPhone, select it as the run destination, Cmd+R.
3. First install: on the phone, Settings → General → VPN & Device Management → trust the profile.
4. Free account note: the signing cert expires every **7 days** — reopen Xcode and Cmd+R to re-sign.

## Regenerating the project

The `.xcodeproj` is generated from `project.yml` with [XcodeGen](https://github.com/yonas/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
```

Edit `project.yml` (not the xcodeproj) when adding targets/settings. New Swift files under `Pi/` are picked up automatically on regenerate (and Xcode also adds them in-place fine).

## Signing in

The app talks to the backend over the JSON API (`/api/*`, `X-Api-Key` auth).

- Default base URL: `http://pi.local:8080` (changeable under **Advanced** on the login screen — point it at your own host; `http://localhost:8080` works for simulator testing).
- Sign in with the email/password of a user row on the server. On first boot after the backend update, the admin account is seeded from the `AUTH_USER` / `AUTH_PASS` env vars (API key reuses `HEALTH_API_KEY`).
- New accounts are created from Settings → Admin → Manage users (admin only).

## What's here

| Area | Files |
|---|---|
| Entry/theme | `Pi/PiApp.swift`, `Pi/Theme/` (xcassets color tokens, light+dark) |
| Auth/session | `Pi/Config/Session.swift`, `Pi/Config/Keychain.swift` |
| Networking | `Pi/Networking/APIClient.swift` (snake_case codec, typed endpoints) |
| Screens | Today, Calendar + day detail, Workout (gym-first logging), Body (charts), Exercises, Sync, Settings (profile / theme / goals / admin users) |
| HealthKit | `Pi/HealthKit/HealthService.swift` — manual "Sync Apple Health now" in Settings |

Deferred from PLAN.md: iOS trends — analytics stay on the web by design.
