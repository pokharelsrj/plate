# Plate — app

The only front end: a SwiftUI iPhone app, a watchOS companion for logging sets
mid-workout, and a widget bundle (Today widget + rest-timer Live Activity).
It talks to [`../backend`](../backend) over JSON with `X-Api-Key` auth.

> The Xcode targets and bundle IDs are still named `Pi`, from before the
> rename. Only the display name says Plate. Renaming the bundle ID would change
> the App Group and Keychain service too, which costs a re-sign and drops any
> stored key — not worth it for a cosmetic change.

## Requirements

- Xcode 15+ (iOS 17 SDK)
- An Apple developer account, free or paid, for installs on a real device

## Open & run

```sh
open Pi.xcodeproj
```

1. Select the **Pi** target → Signing & Capabilities → pick your personal team.
2. Plug in your iPhone, select it as the run destination, Cmd+R.
3. First install: on the phone, Settings → General → VPN & Device Management → trust the profile.
4. Free account note: the signing cert expires every **7 days** — reopen Xcode and Cmd+R to re-sign.

The App Group (`group.com.srijanpokharel.pi`) is what lets the widget see your
data. If the widget shows nothing, check Settings → Diagnostics → Widget cache;
"unavailable" means the entitlement didn't provision.

## Regenerating the project

The `.xcodeproj` is generated from `project.yml` with
[XcodeGen](https://github.com/yonas/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
```

Edit `project.yml`, not the xcodeproj. New Swift files under `Pi/` are picked
up on the next regenerate (and adding them in Xcode directly works fine too).

## Signing in

- Default base URL is `https://api.srijanpokharel.com`. Change it under
  **Advanced** on the login screen — point it at your own server, or
  `http://localhost:8080` against a backend running on your Mac.
- Sign in with the email and password of a user on the server. The first
  account is seeded from the backend's `AUTH_USER` / `AUTH_PASS`.
- More accounts: Settings → Admin → Manage users (admin only).

The API key comes back from login and lives in the Keychain. Rotate it from
Settings if you ever need to.

## What's here

| Area | Files |
|---|---|
| Entry / theme | `Pi/PiApp.swift`, `Pi/Theme/` — semantic color tokens in xcassets, light + dark |
| Auth / session | `Pi/Config/Session.swift`, `Pi/Config/Keychain.swift`, `Pi/Config/AppLock.swift` |
| Networking | `Pi/Networking/APIClient.swift` — snake_case codec, typed endpoints |
| Screens | Today, Calendar + day detail, Workout, Body, Exercises, Trends, Sync, Settings |
| HealthKit | `Pi/HealthKit/` — "Sync Apple Health now" in Settings |
| Watch | `PiWatch/` — log sets and start rest timers from the wrist |
| Widget | `PiWidget/` — Today widget and the rest-timer Live Activity |
| Shared | `Shared/` — App Group cache and Live Activity types, used by all three targets |

`Pi/Models/Models.swift` decodes with `.convertFromSnakeCase`, so JSON keys
with digits in them (`est_1rm`) don't round-trip — the backend uses
`est_one_rm` for exactly that reason.
