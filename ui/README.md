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

## Building from the command line

The project ships a shared `Plate` scheme, so no Xcode session is required:

```sh
xcodegen generate
xcodebuild -scheme Plate -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
```

Use `-destination` rather than `-sdk`, so each target builds for its own
platform rather than all of them against one.

The products are deliberately named apart — `Pi.app` for the phone,
`PlateWatch.app` for the watch — because two bundles called `Pi.app` are easy
to confuse when installing on a simulator by hand. Normally you don't: run the
scheme on an iPhone simulator that has a paired watch and the watch app
installs through the phone, exactly as it does on real hardware.

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

The server address is fixed at `https://api.srijanpokharel.com` — there's no
in-app override, because the shipped app is a client for one instance rather
than a general-purpose one. If you're hacking on this and want a different
backend, change `Session.defaultBaseURL`, or set `PI_TEST_BASE_URL` in the
scheme's environment for a DEBUG build.

- Sign in with the email and password of a user on that server. The first
  account is seeded from the backend's `AUTH_USER` / `AUTH_PASS`.
- **Create an account** appears on the sign-in screen when the server has
  `SIGNUP_INVITE_CODE` set; it needs that code.
- Admins can also add accounts under Settings → Admin → Manage users.

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
