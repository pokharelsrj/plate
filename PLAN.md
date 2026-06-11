# iOS App Build Plan

Native SwiftUI app + widgets, client to the existing Pi-webpage Go backend. Free Apple developer account.

**Key decisions baked in:**
- **Multi-user, admin-only signup** — you create accounts from `/settings/users`; no public signup
- **Shared exercise library and body-part tags**; everything else (workouts, body metrics, health data, gym checkins, nutrition, sync state) is per-user
- **Light + dark theme on iOS** with system-following default; web stays dark-only
- **No Trends in iOS v1** — keep the calendar for review; trends/analytics stay on the web for now
- **Gym-first workout UX** — gesture-based set logging (steppers + swipe-to-clone-last-set + swipe-to-delete) so you can log fast with sweaty hands; editing uses buttons

---

## 1. Project metadata

| Field | Value |
|---|---|
| Bundle ID | `com.srijanpokharel.pi` (personal team — anything unique works) |
| Display name | `Pi` |
| Min iOS version | **17.0** (for `@Observable`, AppIntents in widgets, ContainerView) |
| Targets | (a) Pi app (b) PiWidget extension |
| Language | Swift 5.9+ |
| UI | SwiftUI only — no UIKit |
| Persistence | SwiftData for cache (iOS 17+) — optional; can use JSON-on-disk to start |
| Networking | `URLSession` + async/await |
| Charts | none in v1 (trends are web-only for now) |

## 2. Free Apple dev account: what you actually get

| Feature | Free | Notes |
|---|---|---|
| Sideload to your own device via Xcode | ✅ | Single Mac, USB or wireless |
| HealthKit | ✅ | Toggle in Signing & Capabilities |
| App Groups | ✅ | Required to share data with widget |
| Background Modes | ✅ | Background fetch, processing |
| Widgets (WidgetKit) | ✅ | iOS 14+ |
| Live Activities / Lock Screen widgets | ✅ | iOS 16+ |
| AppIntents (interactive widgets) | ✅ | iOS 17+ |
| Push notifications | ❌ | Need paid; use local notifications instead |
| TestFlight | ❌ | Sideload only |
| App Store | ❌ | Not relevant for personal use |
| Cert expiration | **7 days** | App stops working — must reopen in Xcode and rebuild |
| Concurrent apps installed | 3 max | per device |

**Migration path:** any time you want to upgrade to the $99 paid account, the bundle ID and code don't change — just re-sign with a different team. Don't architect around the free constraints.

## 3. High-level architecture

```
┌────────────────────────────────────────────────────────────┐
│  iOS device                                                │
│                                                            │
│  ┌─────────────┐   App Group   ┌─────────────────────┐    │
│  │   Pi App    │ ◀────────────▶│   PiWidget          │    │
│  │  (SwiftUI)  │  shared cache │   (WidgetKit)       │    │
│  └─────────────┘               └─────────────────────┘    │
│        │                                  ▲                │
│        │ Keychain                         │ Timeline       │
│        │ • api_key                        │ • read cache   │
│        │ • base_url                       │                │
│        │                                                   │
│        ▼  HealthKit                                        │
│  ┌─────────────┐                                           │
│  │  HKStore    │                                           │
│  │  Observers  │                                           │
│  └─────────────┘                                           │
│        │                                                   │
└────────┼───────────────────────────────────────────────────┘
         │                                                    
         │ HTTPS + X-Api-Key                                  
         ▼                                                    
   ┌──────────────────────────────────────┐                  
   │ health.example.com (Caddy)    │                  
   │   ↓                                  │                  
   │ pi-webpage Go service                │                  
   │   ↓                                  │                  
   │ SQLite                               │                  
   └──────────────────────────────────────┘                  
```

**Key decisions:**
- Pi is source of truth — app cache only for UX (offline read, widget speed)
- All app↔Pi traffic uses one base URL + one API key (already public-fronted via Caddy)
- Widgets read from App Group cache; main app refreshes it after every successful API write
- HealthKit reads happen in app, get POSTed to `/api/health/ingest` — same contract as today's iOS Shortcut
- No login UI; one-time API key paste in Settings

## 4. Configuration & Auth

### 4.1 Identity model

| Concept | Storage | Purpose |
|---|---|---|
| `User` row | `users` table on Pi | One row per real person |
| `password_hash` | bcrypt in `users.password_hash` | Web login |
| `api_key` | random 32-byte hex in `users.api_key` | App + HealthKit ingest auth |
| Session cookie | in-memory map on Pi (existing) | Web session |

**Each user has exactly one API key** at any time, persistent until they rotate it. No expiring tokens (keeps things simple; sufficient for personal/family use over a private channel).

### 4.2 Settings storage on device

| Field | Storage | Type |
|---|---|---|
| `apiBaseURL` | UserDefaults (App Group) | String — default `https://health.example.com` |
| `apiKey` | **Keychain** (App Group access) | String |
| `userId` | UserDefaults (App Group) | Int64 (returned at login) |
| `displayName` | UserDefaults (App Group) | String (for greeting + nav) |
| `themePreference` | UserDefaults | `"system" \| "light" \| "dark"` — default `"system"` |
| `lastFullSyncAt` | UserDefaults (App Group) | Date |
| `dailyStepGoal` | UserDefaults | Int — default 10000 |
| `sleepGoalHours` | UserDefaults | Double — default 7.5 |

### 4.3 Keychain spec

```swift
// Service: "com.srijanpokharel.pi.api"
// Account: "primary"
// AccessGroup: "<team-id>.com.srijanpokharel.pi.shared"
// Accessibility: .afterFirstUnlockThisDeviceOnly
// Synchronizable: false
```

The widget must read the API key too, so use App Group keychain access.

### 4.4 Onboarding flow (first launch)

1. Screen shows: **"Sign in to your Pi"** with two fields:
   - **Base URL** (pre-filled `https://health.example.com`, hidden behind an "Advanced" disclosure)
   - **Email**
   - **Password**
2. Tap **Sign in** → `POST /api/auth/login`
3. On success: server returns `{ user, api_key }`. Store key in Keychain, user/displayName in UserDefaults, dismiss
4. On failure: show inline "Invalid credentials" or network error

There is **no public signup** — users tap "Don't have an account?" → shows an info card: *"Ask the admin to create one for you."*

### 4.5 Network layer

```swift
struct APIClient {
    let baseURL: URL
    let apiKey: String

    func request<T: Decodable>(_ path: String,
                                method: String = "GET",
                                body: Encodable? = nil,
                                requiresAuth: Bool = true) async throws -> T

    // Standard headers added to every authed request:
    //   X-Api-Key: <key>
    //   Content-Type: application/json (when body present)
    //   Accept: application/json
}

enum APIError: Error {
    case unauthorized      // 401 — kick to login screen, clear cached key
    case forbidden         // 403 — endpoint requires admin
    case notFound          // 404
    case conflict(String)  // 409 — e.g. duplicate exercise, tag in use
    case server(String)    // 5xx with message
    case decode(Error)     // JSON shape mismatch
    case network(Error)    // URLError
}
```

URLSession config: `waitsForConnectivity = true`, `timeoutIntervalForRequest = 15`. On 401, clear Keychain + show onboarding sheet.

---

## 5. API Contract (server endpoints the app needs)

> All endpoints under `/api/*` are already excluded from the cookie-auth middleware. They auth with `X-Api-Key`. **Endpoints marked NEW must be implemented in Phase 1** before the app can use them.
> 
> **Every authed endpoint resolves the user from the `X-Api-Key` header.** All "user-scoped" tables (workouts, body metrics, health, gym, nutrition, sync runs) are filtered by `user_id`. Shared tables (exercises, body_parts) are not filtered. Admin-only endpoints additionally require `users.role = 'admin'`.

### 5.0 Authentication

#### `POST /api/auth/login` — NEW (public, no auth required)
**Body:** `{ "email": "me@example.com", "password": "..." }`  
**Response 200:**
```json
{
  "user": {
    "id": 1,
    "email": "me@example.com",
    "display_name": "Srijan",
    "role": "admin",
    "date_of_birth": "1990-01-01",
    "sex": "male"
  },
  "api_key": "0000000000000000000000000000000000000000000000000000000000000000"
}
```
**Response 401:** `{ "error": "invalid credentials" }`

#### `GET /api/me` — NEW
Returns the current user (for app to refresh display name, goals, etc.).
**Response 200:** same `user` object as above (without `api_key`).

#### `POST /api/me/rotate-key` — NEW
Generates a new API key for the current user. Returns the new key. Invalidates the old key immediately.  
**Response 200:** `{ "api_key": "<new-key>" }`

#### `PUT /api/me` — NEW
Update own profile.  
**Body:** `{ "display_name": "...", "date_of_birth": "YYYY-MM-DD", "sex": "male\|female" }` — any field optional.

### 5.0.1 Admin: user management (admin only — 403 otherwise)

#### `GET /api/admin/users` — NEW
**Response 200:**
```json
{
  "users": [
    { "id": 1, "email": "...", "display_name": "...", "role": "admin",
      "is_active": true, "created_at": "..." }
  ]
}
```

#### `POST /api/admin/users` — NEW
Create a new user. Server generates `password_hash` from supplied password and a fresh `api_key`.  
**Body:**
```json
{
  "email": "jane@example.com",
  "password": "initial-password",
  "display_name": "Jane",
  "role": "user",
  "date_of_birth": "1995-04-12",
  "sex": "female"
}
```
**Response 201:** the created user record + `api_key` (admin must securely deliver it to the new user; never shown again).

#### `PUT /api/admin/users/{id}` — NEW
Update display name, role, or active status.

#### `POST /api/admin/users/{id}/reset-password` — NEW
**Body:** `{ "password": "new-password" }`. Returns 204.

#### `DELETE /api/admin/users/{id}` — NEW
Hard delete with cascade (drops all user-scoped data). Refuse if `id` is the only admin.

### 5.1 `GET /api/health/ping` — NEW

Sanity check used by onboarding's "Test connection" button. **Public — no auth.**

**Response 200:**
```json
{ "ok": true, "version": "1.0", "server_time": "2026-06-11T20:00:00Z" }
```

### 5.2 `GET /api/today` — NEW

Single roll-up call for the home/dashboard screen. Returns today's snapshot across every module.

**Query params:** `date=YYYY-MM-DD` (optional, defaults to server local today)

**Response 200:**
```json
{
  "date": "2026-06-11",
  "system": {
    "cpu_percent": 23.1,
    "memory_percent": 71.4,
    "disk_percent": 87.0,
    "temp_celsius": 52.3
  },
  "gym": { "checkins": ["2026-06-11T07:45:00-04:00"] },
  "nutrition": {
    "calories": 1850.4, "calorie_budget": 2050.0,
    "protein_g": 142.0, "carb_g": 180.0, "fat_g": 58.0, "fibre_g": 28.5
  },
  "health": {
    "steps": 9123, "active_calories": 411.0, "resting_hr": 58.0,
    "sleep_asleep_h": 7.4, "sleep_deep_h": 1.2,
    "sleep_rem_h": 1.8, "sleep_core_h": 4.2, "sleep_awake_h": 0.2
  },
  "body": { "weight_lbs": 175.5, "bf_percent": 12.8 },
  "workout": {
    "total_sets": 6, "total_volume_lbs": 4730.0,
    "exercise_count": 2,
    "groups": [
      {
        "exercise_id": 1, "exercise_name": "Bench Press", "body_part": "chest",
        "total_volume_lbs": 2510.0,
        "sets": [
          { "id": 12, "reps": 10, "weight_lbs": 135.0 },
          { "id": 13, "reps": 8, "weight_lbs": 145.0 }
        ]
      }
    ]
  }
}
```

Any sub-section may be `null` if no data for that date. App handles null by hiding the card.

### 5.3 `GET /api/calendar?view=month&date=YYYY-MM-DD` — NEW

For the calendar screen.

**Response 200:**
```json
{
  "view": "month",
  "label": "June 2026",
  "prev_date": "2026-05-11",
  "next_date": "2026-07-11",
  "today": "2026-06-11",
  "cells": [
    {
      "date": "2026-05-31", "day": 31, "in_period": false, "is_today": false,
      "has_gym": false, "has_workout": false, "has_weight": false,
      "has_calories": false, "calories": null, "calorie_budget": null,
      "has_steps": false, "steps": null,
      "has_sleep": false, "sleep_hours": null
    }
  ],
  "stats": {
    "gym_days": 3, "avg_calories": 1850, "avg_steps": 9100,
    "avg_sleep_h": 7.3, "workout_days": 4, "total_volume_lbs": 18230
  }
}
```

### 5.4 `GET /api/day?date=YYYY-MM-DD` — NEW

Full detail for one day (calendar day-tap).

**Response 200:** same shape as `/api/today` but for arbitrary date.

### 5.5 Workout endpoints

#### `GET /api/workout?date=YYYY-MM-DD&exercise_id={id}` — NEW
**Response 200:**
```json
{
  "date": "2026-06-11",
  "total_sets": 5, "total_volume_lbs": 4150.0, "exercise_count": 2,
  "groups": [ /* same shape as /api/today.workout.groups */ ],
  "active": {
    "exercise_id": 1,
    "exercise_name": "Bench Press",
    "body_part": "chest",
    "prefill_reps": 10,
    "prefill_weight_lbs": 135.0,
    "today_sets": [ /* WorkoutSet[] */ ],
    "today_volume_lbs": 2510.0,
    "last_session_date": "2026-06-09",
    "last_session_sets": [ /* WorkoutSet[] */ ]
  }
}
```

`active` is omitted when no `exercise_id` query param.

#### `POST /api/workout/set` — NEW
**Body:** `{ "date": "2026-06-11", "exercise_id": 1, "reps": 10, "weight_lbs": 135.0 }`  
`weight_lbs` optional.  
**Response 201:** the created `WorkoutSet`.

#### `PUT /api/workout/set/{id}` — NEW
**Body:** `{ "reps": 12, "weight_lbs": 140.0 }`  
**Response 200:** updated `WorkoutSet`.

#### `DELETE /api/workout/set/{id}` — NEW
**Response 204** on success.

### 5.6 Exercise library

#### `GET /api/exercises` — NEW
**Response 200:**
```json
{
  "exercises": [
    { "id": 1, "name": "Bench Press", "body_part": "chest", "set_count": 24 }
  ],
  "body_parts": ["arms","back","cardio","chest","core","legs","other","shoulders"]
}
```

#### `POST /api/exercises` — NEW
**Body:** `{ "name": "Incline DB Press", "body_part": "chest" }`  
**Response 201:** created Exercise.  
**409** if name already exists.

#### `PUT /api/exercises/{id}` — NEW
**Body:** `{ "name": "Hammer Curl", "body_part": "arms" }`

#### `DELETE /api/exercises/{id}` — NEW
**409** if exercise has sets (returns count in error message).

### 5.7 Body part tags

- `GET /api/body-parts` — `{ "body_parts": [ { "name": "chest", "exercise_count": 4 } ] }`
- `POST /api/body-parts` body `{ "name": "glutes" }`
- `DELETE /api/body-parts/{name}` — **409** if used

### 5.8 Body metrics

#### `GET /api/body?days=60` — NEW
**Response 200:**
```json
{
  "history": [
    {
      "date": "2026-06-11",
      "weight_lbs": 175.5,
      "chest_mm": 12.0, "abdomen_mm": 18.0, "thigh_mm": 14.0,
      "bf_percent": 12.76
    }
  ],
  "latest_weight_lbs": 175.5,
  "latest_bf_percent": 12.76
}
```

#### `POST /api/body` — NEW
Mirror of existing `POST /body`. Any field optional. BF% auto-computed when all 3 calipers present (uses `USER_DOB` env var).

**Body:** `{ "date": "2026-06-11", "weight_lbs": 175.5, "chest_mm": 12, "abdomen_mm": 18, "thigh_mm": 14 }`  
**Response 200:** the upserted record (with `bf_percent` computed).

### 5.9 ~~Trends~~ — skipped for iOS v1

Trends/analytics remain web-only. The existing `/trends/data` route stays unchanged. No iOS endpoint needed.

### 5.10 Health ingest (exists)

`POST /api/health/ingest` — already implemented. App posts deltas after HealthKit reads, same body shape as today's iOS Shortcut.

### 5.11 Sync status

`GET /api/sync` — NEW
```json
{
  "sources": [
    {
      "name": "lafitness", "running": false,
      "last_success_at": "2026-06-11T00:15:23Z",
      "last_records": 3
    }
  ],
  "recent_runs": [
    { "id": 92, "source": "healthifyme", "started_at": "...",
      "completed_at": "...", "status": "success",
      "records_synced": 2, "error_message": null }
  ]
}
```

`POST /api/sync/trigger?source=lafitness&days=60` — kick a sync.

---

## 6. Swift data models

```swift
// All models conform to Codable & Identifiable where appropriate.

struct User: Codable, Identifiable, Hashable {
    let id: Int64
    let email: String
    let displayName: String?
    let role: String                  // "admin" | "user"
    let dateOfBirth: String?          // YYYY-MM-DD
    let sex: String?                  // "male" | "female"
    var isAdmin: Bool { role == "admin" }
}

struct LoginResponse: Codable {
    let user: User
    let apiKey: String
}

struct Exercise: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let bodyPart: String?
    let setCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case bodyPart = "body_part"
        case setCount = "set_count"
    }
}

struct WorkoutSet: Codable, Identifiable, Hashable {
    let id: Int64
    let date: String      // YYYY-MM-DD
    let exerciseId: Int64
    let reps: Int
    let weightLbs: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, reps
        case exerciseId = "exercise_id"
        case weightLbs = "weight_lbs"
    }
}

struct WorkoutGroup: Codable, Identifiable {
    var id: Int64 { exerciseId }
    let exerciseId: Int64
    let exerciseName: String
    let bodyPart: String?
    let totalVolumeLbs: Double
    let sets: [WorkoutSet]
}

struct WorkoutActive: Codable {
    let exerciseId: Int64
    let exerciseName: String
    let bodyPart: String?
    let prefillReps: Int
    let prefillWeightLbs: Double?
    let todaySets: [WorkoutSet]
    let todayVolumeLbs: Double
    let lastSessionDate: String?
    let lastSessionSets: [WorkoutSet]
}

struct BodyMetric: Codable, Identifiable {
    var id: String { date }
    let date: String
    let weightLbs: Double?
    let chestMm: Double?
    let abdomenMm: Double?
    let thighMm: Double?
    let bfPercent: Double?
}

struct HealthDay: Codable {
    let date: String
    let steps: Int?
    let activeCalories: Double?
    let restingHr: Double?
    let sleepAsleepH: Double?
    let sleepDeepH: Double?
    let sleepRemH: Double?
    let sleepCoreH: Double?
    let sleepAwakeH: Double?
}

struct TodaySnapshot: Codable {
    let date: String
    let system: SystemMetrics?
    let gym: GymInfo?
    let nutrition: Nutrition?
    let health: HealthDay?
    let body: BodyMetric?
    let workout: WorkoutSummary?

    struct SystemMetrics: Codable {
        let cpuPercent: Double
        let memoryPercent: Double
        let diskPercent: Double
        let tempCelsius: Double
    }
    struct GymInfo: Codable {
        let checkins: [Date]   // ISO8601 strings decoded via JSONDecoder.dateDecodingStrategy = .iso8601
    }
    struct Nutrition: Codable {
        let calories: Double?
        let calorieBudget: Double?
        let proteinG: Double?
        let carbG: Double?
        let fatG: Double?
        let fibreG: Double?
    }
    struct WorkoutSummary: Codable {
        let totalSets: Int
        let totalVolumeLbs: Double
        let exerciseCount: Int
        let groups: [WorkoutGroup]
    }
}

struct CalendarResponse: Codable {
    let view: String
    let label: String
    let prevDate: String
    let nextDate: String
    let today: String
    let cells: [CalendarCell]
    let stats: CalendarStats

    struct CalendarCell: Codable, Identifiable {
        var id: String { date }
        let date: String
        let day: Int
        let inPeriod: Bool
        let isToday: Bool
        let hasGym: Bool
        let hasWorkout: Bool
        let hasWeight: Bool
        let hasCalories: Bool
        let calories: Double?
        let calorieBudget: Double?
        let hasSteps: Bool
        let steps: Int?
        let hasSleep: Bool
        let sleepHours: Double?
    }

    struct CalendarStats: Codable {
        let gymDays: Int
        let avgCalories: Double
        let avgSteps: Double
        let avgSleepH: Double
        let workoutDays: Int
        let totalVolumeLbs: Double
    }
}

// Trends models intentionally omitted — trends/analytics stay on the web for v1.
```

**Decoder configuration:** custom `JSONDecoder` with `.convertFromSnakeCase` and `.iso8601` for dates (where applicable).

---

## 7. Project layout

```
Pi/
├── Pi.xcodeproj
├── Pi/                          (main app target)
│   ├── PiApp.swift              (entry, @main, theme switch)
│   ├── Info.plist
│   ├── Pi.entitlements          (HealthKit, App Groups)
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset
│   │   ├── PiBg.colorset/       (light + dark appearances)
│   │   ├── PiBg2.colorset/
│   │   ├── PiPrimary.colorset/
│   │   └── ...                  (one per semantic token, see §12)
│   ├── Config/
│   │   ├── Secrets.swift        (loads from Keychain)
│   │   ├── AppGroup.swift       (constants for shared container ID)
│   │   └── Session.swift        (observable: current user + apiKey + apiBaseURL)
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── Endpoints.swift      (typed path builders)
│   │   └── APIError.swift
│   ├── Models/
│   │   └── (the structs from §6)
│   ├── Cache/
│   │   └── SnapshotCache.swift  (today + week, written to App Group)
│   ├── HealthKit/
│   │   ├── HealthService.swift
│   │   ├── HealthSyncTask.swift
│   │   └── HKTypes.swift
│   ├── Screens/
│   │   ├── Login/
│   │   │   └── LoginView.swift
│   │   ├── Today/
│   │   │   ├── TodayView.swift
│   │   │   └── TodayViewModel.swift
│   │   ├── Calendar/
│   │   │   ├── CalendarView.swift
│   │   │   ├── CalendarViewModel.swift
│   │   │   └── DayDetailView.swift
│   │   ├── Workout/
│   │   │   ├── WorkoutView.swift
│   │   │   ├── WorkoutViewModel.swift
│   │   │   └── ExercisePicker.swift
│   │   ├── Exercises/
│   │   │   ├── ExercisesView.swift
│   │   │   ├── ExerciseEditSheet.swift
│   │   │   └── TagManagerView.swift
│   │   ├── Body/
│   │   │   └── BodyView.swift
│   │   ├── Sync/
│   │   │   └── SyncStatusView.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── ProfileView.swift          (edit own profile, rotate API key)
│   │       ├── ThemePickerView.swift      (System / Light / Dark)
│   │       └── AdminUsersView.swift       (admin-only: list + create + delete)
│   ├── Theme/
│   │   ├── Theme.swift            (semantic tokens, palette switch)
│   │   ├── Typography.swift
│   │   └── ViewModifiers.swift    (Card, Pill, etc.)
│   └── Background/
│       └── BackgroundTasks.swift
└── PiWidget/                    (widget extension target)
    ├── PiWidgetBundle.swift
    ├── Info.plist
    ├── PiWidget.entitlements    (App Groups)
    ├── Provider/
    │   └── TodayTimelineProvider.swift
    ├── Views/
    │   ├── SmallTodayWidget.swift
    │   ├── MediumWorkoutWidget.swift
    │   └── LargeOverviewWidget.swift
    └── Intents/
        ├── LogSetIntent.swift   (AppIntent — iOS 17 interactive widget)
        └── RefreshIntent.swift
```

---

## 8. Screens (one section per screen)

### 8.1 Login (Onboarding)

**Shown when:** Keychain has no `apiKey`.

**Fields:**
- **Email** (TextField, keyboard `.emailAddress`, autocapitalization `.never`)
- **Password** (SecureField)
- **Advanced** disclosure → **Base URL** (prefilled `https://health.example.com`)

**Actions:**
- **Sign in** — calls `POST /api/auth/login`. On 200 → save Keychain + UserDefaults → dismiss. On 401 → show "Invalid credentials" inline.
- "Don't have an account?" → opens info modal: *"This is a private service. Ask the admin to create your account."*

**Network test** is implicit (login itself is the test). If the server is unreachable, surface a "Can't reach Pi" error with the base URL shown.

### 8.1.5 Account-switch flow

The app supports one account at a time, but offers easy switch:
- Settings → tap the user row → "Sign out" — clears Keychain + cache, returns to Login.
- Re-login presents the same screen with the previous email pre-filled.

### 8.2 Today (home)

**Tab:** 🏠 (first tab)

**API:** `GET /api/today` on appear + pull-to-refresh.

**Sections (each is a card that hides if data null):**
1. **Status bar** — date + last refresh time
2. **System** — 4 small dials/bars for CPU / Mem / Disk / Temp
3. **Health** — steps (big number), sleep (hours + stacked stage bar), resting HR
4. **Nutrition** — calories vs budget ring + macro bars
5. **Body** — latest weight + BF% (one line each)
6. **Workout** — today's sets grouped by exercise, total volume
7. **Gym checkin** — list of times if any

Tapping any section deep-links to its full screen.

### 8.3 Calendar

**Tab:** 📅

**API:** `GET /api/calendar?view=month&date=...`

**UI:**
- Top bar: `<` prev / month label / `>` next, view toggle (Month / Week)
- 7×N grid of `CalendarCell`s
- Each cell: day number + colored indicator dots matching web (gym/cal/steps/sleep/weight/workout)
- Tap cell → push `DayDetailView` for that date
- Bottom: stats row (gym days, avg cal, avg steps, avg sleep, workouts)

### 8.4 Day detail

**Pushed from:** Calendar.

**API:** `GET /api/day?date=...`

Same structure as Today screen but for arbitrary date. Read-only.

### 8.5 Workout — gym-friendly fast logging

**Tab:** 💪

**Path:** `WorkoutView` is the root.

**Design priority:** you're standing between sets with sweaty hands. **Adding** should be near-zero friction (gestures + big tap targets + haptics). **Editing** can be slower (modal sheet with steppers).

**API calls:**
- `GET /api/workout?date=...&exercise_id=...` on appear / when active exercise changes
- `POST /api/workout/set` on add-set (with optimistic local insert)
- `PUT /api/workout/set/{id}` on edit
- `DELETE /api/workout/set/{id}` on delete (with undo toast)

#### Layout

```
┌──────────────────────────────────────┐
│ [< Jun 11 >]                         │  ← date nav (small)
│  3 exercises · 9 sets · 6,210 lb     │  ← compact stat row
├──────────────────────────────────────┤
│                                      │
│       ACTIVE: Bench Press            │  ← active panel (sticky)
│       chest                          │
│                                      │
│       ╔════════════════════════╗     │
│       ║   −   10 reps   +     ║     │  ← big stepper
│       ╚════════════════════════╝     │
│       ╔════════════════════════╗     │
│       ║  −5   135 lb    +5    ║     │  ← big stepper, custom step
│       ╚════════════════════════╝     │
│                                      │
│       [   ➕   ADD SET            ]  │  ← XL primary button
│       [ ↻ Repeat last set         ]  │  ← secondary, one-tap clone
│                                      │
│  TODAY  ▼                            │  ← collapsible
│   #1  10 × 135 lb         ✎ ─►       │  ← swipe left = delete
│   #2  8 × 140 lb          ✎ ─►       │
│                                      │
│  LAST · Jun 9  ◄─ swipe right        │  ← swipe right pill = clone
│   #1  10 × 130 lb                    │     to TODAY
│   #2  8 × 140 lb                     │
│   #3  6 × 145 lb                     │
│                                      │
├──────────────────────────────────────┤
│  🔍 search exercises...              │
│                                      │
│  chest    [Bench *] [Push-up]        │  ← tap tile to activate
│  back     [Pull-up] [Row]            │
│  legs     [Squat] [Deadlift]         │
└──────────────────────────────────────┘
```

#### Interaction patterns

**A. Big steppers — primary input**

Replace text fields entirely. Steppers are tap-friendly with gym hands.

- **Reps stepper**: `−` / value / `+` — step = 1; long-press for ×3 speed
- **Weight stepper**: `−5` / value / `+5` — step = 5 lb by default; gear icon in corner to switch to 2.5 / 5 / 10 lb increments (persisted per exercise)
- Steppers fill the width and are at least 56pt tall — easy to hit
- Haptic `.impact(.light)` on each tap; `.impact(.medium)` when crossing a "round" value (multiples of 10 reps, 5/10 lb)

```swift
struct GymStepper: View {
    @Binding var value: Double
    let step: Double
    let label: String
    let suffix: String
    var body: some View {
        HStack(spacing: 0) {
            Button("−\(formatStep(step))") { decrement() }
                .frame(maxWidth: .infinity, minHeight: 56)
            Text("\(formatValue(value)) \(suffix)")
                .font(.piMetricLarge)
                .frame(maxWidth: .infinity)
            Button("+\(formatStep(step))") { increment() }
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: value)
    }
}
```

**B. "ADD SET" — single dominant action**

- One huge button (full-width, 64pt tall), `piPrimary` filled
- After tap:
  1. Optimistic insert into TODAY list (animated slide-in from top)
  2. Haptic `.success` notification
  3. POST in background; on failure, revert + toast "couldn't save — tap to retry"
  4. Reps/weight values stay as-is so you can `+5` and tap ADD again for the next set

**C. "↻ Repeat last set" — secondary one-tap clone**

- Below ADD SET; smaller secondary button
- Copies the most recent TODAY set if any, otherwise the latest LAST session set
- Disabled (greyed) when no prior set exists

**D. Swipe gestures — power moves**

| Where | Gesture | Action |
|---|---|---|
| TODAY set row | swipe left | delete (with 5s undo toast at bottom) |
| TODAY set row | swipe right | duplicate (clone as new set after the swiped one) |
| LAST session set row | swipe right (or tap) | clone into TODAY |
| Picker tile | swipe up | quick-add a "repeat last" set without changing active exercise |
| Active panel | swipe left/right on header | cycle to prev/next exercise in current body part |

Use `.swipeActions(edge:allowsFullSwipe:)` for the list-row swipes — native iOS feel. For full-swipe (i.e., commit on long swipe), `allowsFullSwipe: true` on delete only.

**E. Edit — still button-based**

- TODAY set rows show a **pencil ✎** button on the trailing edge
- Tap → sheet rises with the same `GymStepper`s prefilled to that set's values
- "Save" / "Cancel" buttons
- This is the slow path — no need for gestures here, fine to be deliberate

**F. Haptics summary** (using `.sensoryFeedback(...)` in iOS 17)

| Event | Feedback |
|---|---|
| Increment tap | `.impact(weight: .light)` |
| Round-number tick | `.impact(weight: .medium)` |
| Set added | `.success` |
| Set deleted | `.warning` |
| Network failure | `.error` |
| Cycle to next exercise | `.selection` |

**G. Auto-focus loop**

After a set is logged, the cursor logic:
1. Reps stays unchanged (you usually do the same reps next set)
2. Weight stays unchanged
3. No keyboard ever opens (steppers, not text fields)

This way, between sets, you literally tap ADD SET twice in a row to log two identical sets.

**H. Undo toast**

When a set is deleted:
- Set row disappears from TODAY list immediately (optimistic)
- Toast slides up from bottom: "Set deleted · Undo"
- Auto-dismiss after 5s; if Undo is tapped, restore + cancel the pending DELETE
- Implementation: queue the delete behind a 5-second timer; tap-Undo cancels the timer

#### Picker tiles

Below the active panel, all exercises grouped by body part. Tap a tile to set it as active (loads `GET /api/workout?exercise_id=...`).

- Search field above the grid filters tiles by name (client-side)
- Active tile gets `piPrimary` filled background
- Empty-state when search has no matches: "No exercises match — manage library →" deep-links to Exercises.

#### Session summary (collapsible at the very bottom)

Existing pattern from the web: list all exercises performed today with their sets and per-exercise volume. Swipe-to-delete on each set; tap to edit.

### 8.6 Exercises

**Path:** Settings → "Exercises", or from Workout's "manage library" link.

**API:** `GET /api/exercises`, `POST /api/exercises`, `PUT`, `DELETE`, plus tag endpoints.

**UI:**
- "Tags" disclosure group at top — chips with × on unused tags, + Add input
- "New exercise" form: name + body part picker
- List grouped by body part with set count per exercise
- Swipe actions: Edit / Delete (Delete disabled if set_count > 0)

### 8.7 Body

**Tab:** 📊 (or under Settings/More)

**API:** `GET /api/body?days=60`, `POST /api/body`

**UI:**
- Two segmented tabs: "Weight" / "Body Fat"
- **Weight tab:** date picker + weight input + Save → history list of date + weight
- **Body Fat tab:** date picker + chest/abdomen/thigh inputs + Save → history list of date + BF% + 3 measurements
- Charts at top: weight line + BF% line (Swift Charts, 90-day range)

### 8.8 ~~Trends~~ — deferred (web-only for v1)

For trend graphs use the web app at `https://health.example.com/trends`. iOS v1 deliberately ships without analytics so we can focus on data entry and review (Today + Calendar + Workout + Body).

### 8.9 Sync status

**Path:** Settings → Sync.

**API:** `GET /api/sync`, `POST /api/sync/trigger`

**UI:**
- Per-source card: name, last success, records, running indicator
- "Sync now" button → POST trigger
- Recent runs table (last 20)

### 8.10 Settings

**Path:** root tab or Settings icon.

Top of screen — current user row: avatar (initials), display name, email, role pill.

**Sections:**

1. **Account**
   - Edit profile → `ProfileView` (display name, DOB, sex)
   - Rotate API key → confirm dialog → `POST /api/me/rotate-key` → updates Keychain
   - Sign out → clears Keychain, returns to Login
2. **Appearance**
   - Theme: System / Light / Dark (segmented control) — see §12
3. **Goals**
   - Daily step goal (default 10000)
   - Sleep goal hours (default 7.5)
4. **Integrations** *(read-only; configured on Pi via .env)*
   - LA Fitness — shows status (connected/disconnected based on last successful sync)
   - Healthifyme — same
   - Apple Health — toggle to request/revoke HealthKit permissions
5. **Diagnostics**
   - Pi base URL (read-only, edit via re-login)
   - App version + build
   - Last full sync timestamp
   - "Reset cache" button (clears App Group cache)
   - "Force HealthKit re-sync" → `HealthService.sync(daysBack: 7)`
6. **Admin** (visible only when `user.role == "admin"`)
   - Manage users → `AdminUsersView` (§8.11)

### 8.10.1 ProfileView

**Path:** Settings → Edit profile.

Fields: display name, DOB (date picker), sex (segmented: male / female / other).  
Save → `PUT /api/me`.

### 8.10.2 ThemePickerView

**Path:** Settings → Appearance → Theme.

Segmented control: **System / Light / Dark**. Persisted to `themePreference` UserDefaults. Applied to whole app via `.preferredColorScheme(...)` at the root.

### 8.11 AdminUsersView (admin only)

**Path:** Settings → Admin → Manage users.

**API:** `GET /api/admin/users`, `POST /api/admin/users`, `PUT /api/admin/users/{id}`, `POST /api/admin/users/{id}/reset-password`, `DELETE /api/admin/users/{id}`.

**Layout:**
- List of users — each row: avatar, name, email, role pill (admin/user), active toggle
- Tap row → push **UserEditView**: fields above + "Reset password" + "Delete account" (red, with confirm)
- Floating "+" → **NewUserSheet**:
  - email, password, display name, role, DOB, sex
  - Save → `POST /api/admin/users` → returns user + `api_key`
  - **API key display modal** — shown once after creation with copy button and warning: *"Share this securely with the user — they'll need it on first login (their app will fetch their own key once they sign in with email/password). This key won't be shown again."*

Bulk actions (out of scope for v1).

### 8.12 First-launch behavior summary

| State | Shows |
|---|---|
| No saved key | LoginView |
| Saved key + ping fails | LoginView with "Can't reach Pi" banner |
| Saved key + ping 401 | LoginView with "Session expired" banner; pre-fills email |
| Saved key + ping 200 | Today |

---

## 9. HealthKit integration

### 9.1 Entitlements

In `Pi.entitlements`:
```xml
<key>com.apple.developer.healthkit</key><true/>
<key>com.apple.developer.healthkit.access</key>
<array/>   <!-- empty; basic read access -->
<key>com.apple.security.application-groups</key>
<array>
  <string>group.com.srijanpokharel.pi</string>
</array>
```

In `Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>Reads steps, sleep, active energy, and resting heart rate to log them to your Pi.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>(not required — read-only)</string>
```

### 9.2 Types we read

```swift
let read: Set<HKObjectType> = [
    .quantityType(.stepCount),
    .quantityType(.activeEnergyBurned),
    .quantityType(.restingHeartRate),
    .categoryType(.sleepAnalysis)
]
```

### 9.3 HealthService API

```swift
@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()
    private let store = HKHealthStore()
    @Published private(set) var isAuthorized = false

    func requestAuthorization() async throws

    /// Reads a date's HealthDay payload from HealthKit
    func read(date: Date) async throws -> HealthDay

    /// Pushes the last `daysBack` days of HealthKit data to the Pi
    func sync(daysBack: Int = 7) async throws

    /// Long-lived observers that wake the app and trigger sync()
    func startBackgroundObservers()
}
```

**Read details:**
- Steps: `HKStatisticsQuery` with `.cumulativeSum` from `startOfDay(date)` to `startOfDay(date+1)`
- Active energy: same, kcal
- Resting HR: `HKSampleQuery` for samples in day → average value
- Sleep: `HKSampleQuery` over the night that ends on the target date; bucket by `HKCategoryValueSleepAnalysis`:
  - `.awake` → `sleep_awake_h`
  - `.asleepCore` → `sleep_core_h`
  - `.asleepDeep` → `sleep_deep_h`
  - `.asleepREM` → `sleep_rem_h`
  - Sum of (Core+Deep+REM) → `sleep_asleep_h`

**Sync implementation:**
- Build `[HealthDay]` for last `daysBack` days
- POST to `/api/health/ingest` with batched body
- Server's COALESCE upsert means partial payloads are fine

### 9.4 Background observers

```swift
func startBackgroundObservers() {
    let stepType = HKQuantityType(.stepCount)
    let q = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completion, _ in
        Task { try? await self.sync(daysBack: 2) }
        completion()
    }
    store.execute(q)
    store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { _, _ in }
}
```

Register same observers for all 4 types. iOS wakes the app, observer fires, sync runs.

### 9.5 Sleep timing edge case

Sleep recorded between midnight and ~noon belongs to the **previous** calendar day in HealthKit. When pushing sleep, assign it to the `endDate.day - 1`. Same convention the iOS Shortcut used.

---

## 10. Widgets

### 10.1 App Group setup

- ID: `group.com.srijanpokharel.pi`
- Enabled on both main app and widget extension
- Both targets share `UserDefaults(suiteName: groupID)` and Keychain access group

### 10.2 Shared cache

`SnapshotCache.swift` writes a `TodaySnapshot` to:
```
FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: groupID)
    .appendingPathComponent("today.json")
```

Refreshed by main app after every successful Today fetch. Widget reads on every timeline refresh.

### 10.3 Three widget sizes

#### SmallTodayWidget (155×155 / 169×169)
```
┌─────────────────────┐
│  TODAY              │
│                     │
│  9,234 steps        │
│  2,510 lb volume    │
│  7.4h sleep         │
└─────────────────────┘
```
Single column, compact.

#### MediumWorkoutWidget (338×158)
```
┌──────────────────────────────────┐
│  TODAY · 2 ex · 6 sets · 4730 lb │
│                                  │
│  Bench Press  10×135  8×145      │
│  Squat        12×185  10×195     │
│                                  │
│  [ Log set ⏵ ]                   │
└──────────────────────────────────┘
```
Tap the "Log set" button → opens the app to the active exercise. On iOS 17 with AppIntent, can also do quick-log inline.

#### LargeOverviewWidget (338×354)
```
┌──────────────────────────────────┐
│  WEEK OVERVIEW                   │
│  ▤ M T W T F S S                 │
│  steps  ███▃ █▄▆██               │
│  gym    · · · · ✓ · ✓            │
│  workout ✓ · ✓ · ✓ · ✓            │
│  sleep  7.2 8 6.8 7.5 ...        │
│  ────────────────────────────    │
│  TODAY  9,234 steps · 4,730 lb   │
└──────────────────────────────────┘
```

### 10.4 Timeline provider

```swift
struct TodayTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { ... }
    func getSnapshot(in context: Context, completion: ...) { ... }
    func getTimeline(in context: Context, completion: ...) {
        // 1. Read cached snapshot from App Group
        // 2. Emit entry now + every 15 minutes for next 4 hours
        // 3. Policy: .after(now + 4h)
    }
}
```

Widget never makes network calls (App Extension limits + battery). Main app refreshes the cache.

### 10.5 AppIntent (iOS 17 interactive widget)

```swift
struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Set"
    @Parameter(title: "Exercise ID") var exerciseId: Int
    @Parameter(title: "Reps") var reps: Int
    @Parameter(title: "Weight") var weight: Double?

    func perform() async throws -> some IntentResult {
        try await APIClient.shared.logSet(...)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

Tap-to-log-same-as-last-set: button in Medium widget bound to this intent with `last_reps` and `last_weight` pre-filled.

---

## 11. Background tasks

### 11.1 Registration

In `Info.plist`:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.srijanpokharel.pi.refresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>processing</string>
</array>
```

### 11.2 BGAppRefreshTask handler

```swift
// In PiApp.init:
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.srijanpokharel.pi.refresh",
    using: nil
) { task in
    handleAppRefresh(task: task as! BGAppRefreshTask)
}

func scheduleNextRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: "com.srijanpokharel.pi.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleNextRefresh()
    Task {
        try? await HealthService.shared.sync(daysBack: 2)
        try? await SnapshotCache.refreshToday()
        WidgetCenter.shared.reloadAllTimelines()
        task.setTaskCompleted(success: true)
    }
}
```

iOS will throttle aggressively; combined with HealthKit observers this gives ~hourly updates in practice.

---

## 12. Theme — light + dark

### 12.0 Visual direction (iOS only)

The iOS app drops the web's hacker/terminal aesthetic. Instead:
- **Friendly, native iOS feel** — SF Pro Rounded for headlines and big numbers, SF Pro for body
- **No monospace fonts anywhere** in normal UI
- **Soft, rounded corners** (12–16pt for cards, 8pt for inputs/buttons)
- **Generous whitespace**, larger touch targets than the web
- **Subtle shadows + borders** instead of glow effects
- **Functional colors stay vibrant** so gym/sleep/workout indicators remain instantly recognizable across light and dark

Web continues to use the dark hacker theme — these are two intentionally different surfaces for the same data.

### 12.1 Palettes

The iOS app supports **System (auto), Light, Dark**. Use **semantic tokens** that resolve per appearance.

#### Dark palette (modern dark, not terminal)

| Token | Hex | Usage |
|---|---|---|
| `PiBg` | `#0B0F14` | App background |
| `PiBg2` | `#131A22` | Cards |
| `PiBg3` | `#1C242E` | Inputs, inset wells |
| `PiBorder` | `#2A323D` | Borders, dividers |
| `PiText` | `#E8EDF2` | Primary text (warm white) |
| `PiTextMuted` | `#94A3B8` | Secondary text, labels |
| `PiPrimary` | `#4ADE80` | Accent — modern green, not neon |
| `PiPrimaryDim` | `#22C55E` | Pressed primary |
| `PiOnPrimary` | `#0B0F14` | Text on primary-filled buttons |

#### Light palette

| Token | Hex | Usage |
|---|---|---|
| `PiBg` | `#F8FAFC` | App background (slightly off-white) |
| `PiBg2` | `#FFFFFF` | Cards |
| `PiBg3` | `#F1F5F9` | Inputs, inset wells |
| `PiBorder` | `#E2E8F0` | Borders, dividers |
| `PiText` | `#0F172A` | Primary text |
| `PiTextMuted` | `#64748B` | Secondary text, labels |
| `PiPrimary` | `#16A34A` | Accent — darker green for AA contrast on white |
| `PiPrimaryDim` | `#15803D` | Pressed primary |
| `PiOnPrimary` | `#FFFFFF` | Text on primary-filled buttons |

#### Functional colors (light/dark pairs)

Used for gym/steps/sleep/workout indicators. Each has a light and dark hex for AA contrast on its bg. SwiftUI Color sets in xcassets handle this per appearance.

| Token | Dark | Light | Usage |
|---|---|---|---|
| `PiGymCyan` | `#00D4FF` | `#0891B2` | Gym checkin dots, gym summary |
| `PiStepsOrange` | `#FF9500` | `#C2410C` | Steps |
| `PiSleepPurple` | `#AF52DE` | `#7C3AED` | Sleep total |
| `PiSleepDeep` | `#5E34A8` | `#5B21B6` | Deep sleep stage |
| `PiSleepRem` | `#AF52DE` | `#9333EA` | REM stage |
| `PiSleepCore` | `#C896E6` | `#A78BFA` | Core stage |
| `PiSleepAwake` | `#6B6B6B` | `#9CA3AF` | Awake stage |
| `PiWeightTeal` | `#5CE1E6` | `#0E7490` | Body weight |
| `PiBFPink` | `#FF70B3` | `#BE185D` | Body fat % |
| `PiWorkoutGold` | `#FFD166` | `#B45309` | Workout volume, active exercise |
| `PiCalGood` | `#00FF88` | `#16A34A` | Calories on budget |
| `PiCalLow` | `#FFAA00` | `#D97706` | Calories under |
| `PiCalOver` | `#FF4422` | `#DC2626` | Calories over |
| `PiWarn` | `#FFAA00` | `#D97706` | Warnings |
| `PiDanger` | `#FF4422` | `#DC2626` | Destructive actions |

### 12.2 Implementation pattern

**Use xcassets color sets**, not hardcoded hex. Each color set has two appearances (Any/Dark) so SwiftUI automatically picks the right hex based on the current `colorScheme`:

```
Assets.xcassets/
├── PiBg.colorset/Contents.json    (Any: #FAFBFC, Dark: #080C10)
├── PiBg2.colorset/                (Any: #FFFFFF, Dark: #0D1117)
├── PiPrimary.colorset/            (Any: #15803D, Dark: #00FF88)
└── ... (one per token in 12.1)
```

In code:
```swift
extension Color {
    static let piBg         = Color("PiBg")
    static let piBg2        = Color("PiBg2")
    static let piPrimary    = Color("PiPrimary")
    static let piText       = Color("PiText")
    static let piTextMuted  = Color("PiTextMuted")
    static let piBorder     = Color("PiBorder")
    // ... etc
}
```

Never reference hex directly outside `Theme.swift`.

### 12.3 Theme override

`@AppStorage("themePreference") var themePreference: String = "system"`

At the app root:

```swift
@main
struct PiApp: App {
    @AppStorage("themePreference") var themePreference: String = "system"

    var preferredColorScheme: ColorScheme? {
        switch themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil   // system
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
```

When `themePreference == "system"`, SwiftUI inherits from iOS Settings → Display & Brightness.

### 12.4 Widgets and theming

Widgets pick up the system appearance automatically. Same xcassets color tokens work in the widget target — make sure the xcassets file is in both targets (Build Phases → Copy Bundle Resources).

The app's theme override **does NOT** apply to widgets — widgets always follow the system. (That's an iOS limitation, not a choice.) Acceptable since the visual identity is preserved either way.

### 12.5 Typography

**Pleasant, modern, all-native — no monospace, no custom font bundling.**

Apple's system fonts in two flavors:
- **SF Pro Rounded** for headlines, big metric numbers, and primary buttons — friendlier, fitness-app feel
- **SF Pro** (standard) for body, labels, captions — maximum legibility

Use `Font.system(size:weight:design:)`. Centralize tokens in `Theme/Typography.swift`:

```swift
extension Font {
    // Display & headlines (rounded)
    static let piLargeTitle  = Font.system(size: 34, weight: .bold,     design: .rounded)
    static let piTitle       = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let piTitle2      = Font.system(size: 17, weight: .semibold, design: .rounded)

    // Body (default SF Pro)
    static let piHeadline    = Font.system(size: 17, weight: .semibold)
    static let piBody        = Font.system(size: 16, weight: .regular)
    static let piCallout     = Font.system(size: 15, weight: .regular)
    static let piSubheadline = Font.system(size: 14, weight: .regular)
    static let piCaption     = Font.system(size: 12, weight: .regular)

    // Metric numbers (rounded — feels right for big numerals)
    static let piMetricXL    = Font.system(size: 48, weight: .bold,     design: .rounded)
    static let piMetricLarge = Font.system(size: 32, weight: .bold,     design: .rounded)
    static let piMetricMed   = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let piMetricSmall = Font.system(size: 17, weight: .medium,   design: .rounded)

    // Letter-spaced category labels (e.g. "TODAY", "STEPS")
    static let piEyebrow     = Font.system(size: 11, weight: .semibold)
}
```

Usage examples:

| Place | Token |
|---|---|
| Tab title "Today" | `piLargeTitle` |
| Card title "Workout" | `piTitle` |
| Exercise name "Bench Press" | `piHeadline` |
| Set row "10 reps × 135 lb" | `piBody` |
| Big step count "9,234" | `piMetricLarge` |
| Inline volume "4,730 lb" | `piMetricMed` |
| Section label "STEPS" (with `.tracking(1.5)`) | `piEyebrow` |
| Timestamp "Updated 5 min ago" | `piCaption` |

**Letter-spacing** (eyebrow labels): `Text("STEPS").font(.piEyebrow).tracking(1.5).foregroundStyle(.piTextMuted)`.

**Dynamic Type:** these are fixed sizes for visual polish, but the app should respect users' accessibility text size preferences via SwiftUI's automatic Dynamic Type scaling on `Text` views — keep `minimumScaleFactor(0.85)` on critical numerals to avoid overflow.

**No monospace anywhere** in standard UI. The one exception: if you ever surface raw JSON in a dev/debug panel, use `Font.system(.body, design: .monospaced)` there only.

### 12.6 Accessibility

- All semantic colors meet WCAG AA contrast on their corresponding background in **both** light and dark
- Functional colors (gym, sleep stages, etc.) accompanied by labels — never color-alone
- Respect `@Environment(\.dynamicTypeSize)` — avoid hardcoded font sizes for body text; use `Font.system(.body)` etc.
- Reduce-motion support: skip the active-panel glow animation when enabled

---

## 13. Phased roadmap

Each phase is independently shippable to your phone.

### Phase 0 (Pi backend, multi-user migration) — DO THIS FIRST
- Add `users` table (see §18)
- Add `user_id` column to per-user tables: `gym_checkins`, `nutrition_days`, `health_days`, `workout_sets`, `body_metrics`, `sync_runs`
- Add `user_integrations` table for per-user LA Fitness / Healthifyme credentials (move from env vars)
- Seed one admin user from existing `AUTH_USER`/`AUTH_PASS` env vars; assign all existing data to user_id=1
- Update existing handlers to filter by `user_id` (from cookie session or API key)
- Update cron scheduler to iterate users × sources
- New web pages: `/login` (now uses email+password), `/settings/users` (admin only)

### Phase 1 (Pi backend, JSON API)
- Implement every NEW endpoint listed in §5 (including `/api/auth/login`, `/api/admin/users/*`, `/api/me`)
- Reuse the db layer; add JSON response shaping layer
- Confirm all `/api/*` endpoints resolve user from `X-Api-Key` and filter user-scoped data
- Curl tests for every endpoint with multiple test users

### Phase 2 (Xcode — scaffold + theme + login)
- New Xcode project, add Widget target, App Group + Keychain group
- xcassets color sets for every semantic token (light + dark, §12.1)
- Theme picker in Settings stub
- APIClient + all model structs
- LoginView (POST /api/auth/login)
- Skeleton tabs (5 tabs, empty screens with title)

### Phase 3 (Today + Calendar)
- Implement Today (read-only)
- Implement Calendar + Day Detail
- Pull-to-refresh, optimistic local cache to App Group

### Phase 4 (Workout flow)
- Workout screen with the active-panel pattern
- Add/Edit/Delete sets
- Exercise picker with search

### Phase 5 (Body + Exercises management)
- Body weight + BF entry, history list, charts
- Exercises CRUD + tag management

### Phase 6 (deferred — Trends on iOS)
Skipped for v1. Use the web app for graphs. Re-introduce after the rest of the app stabilizes.

### Phase 7 (HealthKit auto-sync)
- HKAuthorization on first use
- Per-day reads
- Push to `/api/health/ingest`
- Background observers + BGAppRefreshTask

### Phase 8 (Widgets)
- Small/Medium/Large widgets reading App Group cache
- AppIntent for tap-to-log-set
- Timeline refresh policy

### Phase 9 (Polish)
- Settings screen
- Profile editor + admin user management screen
- Sync status screen
- Local notifications (e.g., "haven't logged dinner")
- Error states + offline handling
- Onboarding pre-fill via QR code (admin generates a QR for new user containing base URL + temp password)

---

## 14. Out of scope (explicit)

- App Store distribution
- Push notifications
- Multi-user / sharing
- iCloud sync (the Pi is the cloud)
- Apple Watch app — possible later but skip for v1
- iPad-optimized layouts — works as scaled iPhone

---

## 15. Open questions for you

1. **Tab order / which tabs should be on the bottom bar?** Suggested: Today / Calendar / Workout / Body / Settings (5 tabs, no Trends in v1).
2. **Daily step goal & sleep goal** — current defaults (10k steps, 7.5h) okay or other targets?
3. **Widget tap behavior** — open app vs. one-tap-log-same-as-last-set vs. both per widget size?
4. **Quiet hours for HealthKit sync** — sync continuously, or only between 6am–midnight?
5. **Theme default** — System (recommended), Light, or Dark?
6. **Initial admin user** — keep your existing `AUTH_USER`/`AUTH_PASS` as the admin credentials, or set new ones during migration?
7. **Onboarding for new users** — admin types initial password and shares it via Signal/iMessage, or admin generates a one-time setup link with embedded credentials?
8. **Display name format** — first name only, or full name (affects greeting on Today screen)?

---

## 16. Build/sign workflow with free dev account

1. In Xcode, Signing & Capabilities → Team: select your personal team
2. Bundle ID has to be globally unique even on free — use `com.srijanpokharel.pi` (already unique enough)
3. Plug iPhone → select as run target → Cmd+R
4. First run on the phone: Settings → General → VPN & Device Management → trust the dev profile
5. **Every 7 days:** open Xcode → Cmd+R again to re-sign. The app icon stays put; the cert renews.
6. If you upgrade to paid: change Team in Xcode, rebuild once. Bundle ID and code stay identical.

---

## 17. Server work checklist (what to do next here)

### Phase 0 — Multi-user migration
- [ ] Create `users` table + `user_integrations` table (§18)
- [ ] Add `user_id` column to: `gym_checkins`, `nutrition_days`, `health_days`, `workout_sets`, `body_metrics`, `sync_runs`
- [ ] Migration script: insert admin user from env, assign existing rows to that user
- [ ] Replace single `AUTH_USER`/`AUTH_PASS` env auth with user-table lookup (bcrypt)
- [ ] Replace single `HEALTH_API_KEY` env auth with `users.api_key` lookup
- [ ] Move LA Fitness / Healthifyme creds from env vars to `user_integrations` rows
- [ ] Update cron scheduler to iterate users × sources
- [ ] Update all existing handlers to filter user-scoped queries by `user_id` from session or API key
- [ ] Add `/settings/users` admin web page (HTML, mirrors AdminUsersView)

### Phase 1 — API endpoints (JSON, X-Api-Key auth)

**Auth & user**
- [ ] `POST /api/auth/login`
- [ ] `GET /api/me`
- [ ] `PUT /api/me`
- [ ] `POST /api/me/rotate-key`

**Admin user management**
- [ ] `GET /api/admin/users`
- [ ] `POST /api/admin/users`
- [ ] `PUT /api/admin/users/{id}`
- [ ] `POST /api/admin/users/{id}/reset-password`
- [ ] `DELETE /api/admin/users/{id}`

**Health & ping**
- [ ] `GET /api/health/ping` (public)

**Today / calendar**
- [ ] `GET /api/today`
- [ ] `GET /api/day?date=`
- [ ] `GET /api/calendar?view=&date=`

**Workout**
- [ ] `GET /api/workout?date=&exercise_id=`
- [ ] `POST /api/workout/set`
- [ ] `PUT /api/workout/set/{id}`
- [ ] `DELETE /api/workout/set/{id}`

**Exercises (shared library)**
- [ ] `GET /api/exercises`
- [ ] `POST /api/exercises`
- [ ] `PUT /api/exercises/{id}`
- [ ] `DELETE /api/exercises/{id}`
- [ ] `GET /api/body-parts`
- [ ] `POST /api/body-parts`
- [ ] `DELETE /api/body-parts/{name}`

**Body**
- [ ] `GET /api/body?days=`
- [ ] `POST /api/body`

**Sync**
- [ ] `GET /api/sync`
- [ ] `POST /api/sync/trigger?source=&days=`

**Trends (web-only — skip for iOS v1)**
- ~~`GET /api/trends?range=`~~ — keep on the existing web route; iOS app does not consume this in v1.

After Phase 0 + Phase 1 are live, the iOS app project can be started in Xcode with zero further backend work for v1.

---

## 18. Multi-user database migration

### 18.1 Schema additions

```sql
CREATE TABLE IF NOT EXISTS users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    email           TEXT UNIQUE NOT NULL COLLATE NOCASE,
    display_name    TEXT,
    password_hash   TEXT NOT NULL,          -- bcrypt
    api_key         TEXT UNIQUE NOT NULL,   -- 32-byte hex
    role            TEXT NOT NULL DEFAULT 'user',  -- 'admin' | 'user'
    date_of_birth   TEXT,                   -- YYYY-MM-DD
    sex             TEXT,                   -- 'male' | 'female' | NULL
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_users_api_key ON users(api_key);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email COLLATE NOCASE);

CREATE TABLE IF NOT EXISTS user_integrations (
    user_id      INTEGER NOT NULL,
    source       TEXT NOT NULL,             -- 'lafitness' | 'healthifyme'
    credentials  TEXT NOT NULL,             -- JSON: source-specific (username/password/api_key/etc.)
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, source),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### 18.2 Add `user_id` to per-user tables

For each of: `gym_checkins`, `nutrition_days`, `health_days`, `workout_sets`, `body_metrics`, `sync_runs`:

1. Add column `user_id INTEGER NOT NULL DEFAULT 1`
2. Add index on `(user_id, date)` where applicable
3. For tables with composite primary keys involving date (`nutrition_days`, `health_days`, `body_metrics`), change PK to `(user_id, date)`

```sql
-- nutrition_days
ALTER TABLE nutrition_days ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1;
-- (SQLite can't drop a primary key; rebuild via CREATE TABLE new, INSERT SELECT, DROP, RENAME)

-- workout_sets, gym_checkins, sync_runs
ALTER TABLE workout_sets ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1;
CREATE INDEX IF NOT EXISTS idx_ws_user_date ON workout_sets(user_id, date);
-- (same pattern for gym_checkins, sync_runs)
```

Shared tables `exercises` and `body_parts` are **not** modified — they remain global.

### 18.3 Migration script (run once on first start after deploy)

In Go:

```go
func migrateToMultiUser() error {
    // Step 1: create users + user_integrations tables (idempotent IF NOT EXISTS)
    // Step 2: if users table empty, seed admin from env vars
    if userCount() == 0 {
        email := os.Getenv("AUTH_USER")        // existing
        password := os.Getenv("AUTH_PASS")
        dob := os.Getenv("USER_DOB")
        hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
        apiKey := os.Getenv("HEALTH_API_KEY")  // reuse existing key for backward compat
        if apiKey == "" { apiKey = randomHex(32) }
        db.Exec(`INSERT INTO users (email, display_name, password_hash, api_key, role, date_of_birth, sex)
                 VALUES (?, ?, ?, ?, 'admin', ?, 'male')`,
                 email, "Admin", hash, apiKey, dob)
        adminID := int64(1)

        // Migrate integrations
        if u := os.Getenv("LAFITNESS_USER"); u != "" {
            creds, _ := json.Marshal(map[string]string{
                "username": u,
                "password": os.Getenv("LAFITNESS_PASS"),
            })
            db.Exec(`INSERT INTO user_integrations (user_id, source, credentials) VALUES (?, 'lafitness', ?)`, adminID, string(creds))
        }
        if k := os.Getenv("HEALTHIFYME_API_KEY"); k != "" {
            creds, _ := json.Marshal(map[string]string{
                "api_key": k,
                "user_id": os.Getenv("HEALTHIFYME_USER_ID"),
            })
            db.Exec(`INSERT INTO user_integrations (user_id, source, credentials) VALUES (?, 'healthifyme', ?)`, adminID, string(creds))
        }
    }
    // Step 3: add user_id columns + indexes if missing (introspect schema)
    return nil
}
```

After migration succeeds, the env vars (`AUTH_USER`, `AUTH_PASS`, `HEALTH_API_KEY`, `LAFITNESS_*`, `HEALTHIFYME_*`, `USER_DOB`) become **legacy/optional** — only consulted to seed the admin on a fresh database. The DB becomes the source of truth.

### 18.4 Existing handler updates (Phase 0)

Every handler that touches user-scoped data needs to know the current user:

```go
// auth middleware adds *User to request context
type ctxKey int
const userKey ctxKey = 0

func currentUser(r *http.Request) *db.User {
    u, _ := r.Context().Value(userKey).(*db.User)
    return u
}
```

Existing DB functions get a `userID` parameter prepended:

```go
// before
func CheckinDatesBetween(from, to time.Time) (map[string][]time.Time, error)

// after
func CheckinDatesBetween(userID int64, from, to time.Time) (map[string][]time.Time, error)
```

This is mechanical but pervasive — every call site updates.

### 18.5 Cron scheduler update

Today's `Sources` is a list of `(name, func)`. Becomes a list of `(name, perUserFunc)` and the runner iterates users:

```go
for _, src := range Sources {
    users, _ := db.UsersWithIntegration(src.Name)  // SELECT users JOIN user_integrations
    for _, u := range users {
        RunSourceForUser(ctx, src, u, src.Daily)
    }
}
```

Each user's `sync_runs` row carries `user_id`, so the sync status page filters by current user.

### 18.6 Web UI changes (mirror, not full redesign)

- `/login` — change form fields from username/password (env) to email/password (DB lookup)
- `/settings` — add Account section + Users admin link
- `/settings/users` — list, create, edit, delete users (admin only); 403 redirect for non-admins
- All existing pages — no template changes; data already filters by user via middleware
- Top bar nav — show current user display name; "sign out" stays in dropdown

This keeps the web UI dark-only as requested while still benefiting from multi-user backend.
