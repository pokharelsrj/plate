//go:generate templ generate

package main

import (
	"log"
	"net/http"
	"os"

	"pi-webpage/db"
	"pi-webpage/handlers"
	"pi-webpage/sync"
)

func main() {
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "data.db"
	}
	if err := db.Open(dbPath); err != nil {
		log.Fatalf("db open: %v", err)
	}
	if err := db.SeedAdminFromEnv(); err != nil {
		log.Printf("admin seed: %v", err)
	}

	sync.StartScheduler()
	sync.MaybeInitialBackfill()

	mux := http.NewServeMux()

	// Auth
	mux.HandleFunc("GET /login", handlers.LoginPage)
	mux.HandleFunc("POST /login", handlers.LoginSubmit)
	mux.HandleFunc("POST /logout", handlers.Logout)

	// Fitness calendar — also the home page. "/" is registered exactly (`{$}`)
	// so unknown paths fall through to the 404 below instead of rendering it.
	mux.HandleFunc("GET /{$}", handlers.FitnessPage)
	mux.HandleFunc("GET /fitness", handlers.FitnessPage)
	mux.HandleFunc("GET /fitness/grid", handlers.FitnessGrid)
	mux.HandleFunc("GET /fitness/day", handlers.FitnessDayDetail)

	// Body metrics (weight, BF%)
	mux.HandleFunc("GET /body", handlers.BodyPage)
	mux.HandleFunc("POST /body", handlers.BodySubmit)

	// Workout tracker
	mux.HandleFunc("GET /workout", handlers.WorkoutPage)
	mux.HandleFunc("POST /workout/set", handlers.WorkoutAddSet)
	mux.HandleFunc("POST /workout/set/update", handlers.WorkoutUpdateSet)
	mux.HandleFunc("POST /workout/set/delete", handlers.WorkoutDeleteSet)

	// Workout stats (lifting analytics)
	mux.HandleFunc("GET /workout/stats", handlers.WorkoutStatsPage)
	mux.HandleFunc("GET /workout/stats/data", handlers.WorkoutStatsData)

	// Exercise library
	mux.HandleFunc("GET /exercises", handlers.ExercisesPage)
	mux.HandleFunc("POST /exercises", handlers.ExerciseCreate)
	mux.HandleFunc("POST /exercises/update", handlers.ExerciseUpdate)
	mux.HandleFunc("POST /exercises/delete", handlers.ExerciseDelete)
	mux.HandleFunc("POST /exercises/tag", handlers.BodyPartCreate)
	mux.HandleFunc("POST /exercises/tag/delete", handlers.BodyPartDelete)

	// Trends
	mux.HandleFunc("GET /trends", handlers.TrendsPage)
	mux.HandleFunc("GET /trends/data", handlers.TrendsData)

	// Sync status
	mux.HandleFunc("GET /sync", handlers.SyncStatusPage)
	mux.HandleFunc("GET /sync/status/fragment", handlers.SyncStatusFragment)
	mux.HandleFunc("POST /sync/trigger", handlers.SyncTrigger)

	// Apple Health ingestion (API key auth via X-Api-Key, bypasses cookie auth)
	mux.HandleFunc("POST /api/health/ingest", handlers.HealthIngest)

	// JSON API for the iOS app (X-Api-Key auth; /api/* bypasses cookie auth)
	mux.HandleFunc("POST /api/auth/login", handlers.APILogin)
	mux.HandleFunc("GET /api/health/ping", handlers.APIPing)
	mux.HandleFunc("GET /api/me", handlers.WithAPIKey(handlers.APIMe))
	mux.HandleFunc("PUT /api/me", handlers.WithAPIKey(handlers.APIMeUpdate))
	mux.HandleFunc("POST /api/me/rotate-key", handlers.WithAPIKey(handlers.APIRotateKey))

	mux.HandleFunc("GET /api/admin/users", handlers.WithAdmin(handlers.APIAdminListUsers))
	mux.HandleFunc("POST /api/admin/users", handlers.WithAdmin(handlers.APIAdminCreateUser))
	mux.HandleFunc("PUT /api/admin/users/{id}", handlers.WithAdmin(handlers.APIAdminUpdateUser))
	mux.HandleFunc("POST /api/admin/users/{id}/reset-password", handlers.WithAdmin(handlers.APIAdminResetPassword))
	mux.HandleFunc("DELETE /api/admin/users/{id}", handlers.WithAdmin(handlers.APIAdminDeleteUser))

	mux.HandleFunc("GET /api/today", handlers.WithAPIKey(handlers.APIToday))
	mux.HandleFunc("GET /api/day", handlers.WithAPIKey(handlers.APIToday))
	mux.HandleFunc("GET /api/calendar", handlers.WithAPIKey(handlers.APICalendar))

	mux.HandleFunc("GET /api/workout", handlers.WithAPIKey(handlers.APIWorkout))
	mux.HandleFunc("GET /api/workout/stats", handlers.WithAPIKey(handlers.APIWorkoutStats))
	mux.HandleFunc("POST /api/workout/set", handlers.WithAPIKey(handlers.APIWorkoutAddSet))
	mux.HandleFunc("PUT /api/workout/set/{id}", handlers.WithAPIKey(handlers.APIWorkoutUpdateSet))
	mux.HandleFunc("DELETE /api/workout/set/{id}", handlers.WithAPIKey(handlers.APIWorkoutDeleteSet))

	mux.HandleFunc("GET /api/exercises", handlers.WithAPIKey(handlers.APIExercises))
	mux.HandleFunc("POST /api/exercises", handlers.WithAPIKey(handlers.APIExerciseCreate))
	mux.HandleFunc("PUT /api/exercises/{id}", handlers.WithAPIKey(handlers.APIExerciseUpdate))
	mux.HandleFunc("DELETE /api/exercises/{id}", handlers.WithAPIKey(handlers.APIExerciseDelete))

	mux.HandleFunc("GET /api/body-parts", handlers.WithAPIKey(handlers.APIBodyParts))
	mux.HandleFunc("POST /api/body-parts", handlers.WithAPIKey(handlers.APIBodyPartCreate))
	mux.HandleFunc("DELETE /api/body-parts/{name}", handlers.WithAPIKey(handlers.APIBodyPartDelete))

	mux.HandleFunc("GET /api/body", handlers.WithAPIKey(handlers.APIBody))
	mux.HandleFunc("POST /api/body", handlers.WithAPIKey(handlers.APIBodySubmit))

	mux.HandleFunc("GET /api/trends", handlers.WithAPIKey(handlers.APITrends))

	mux.HandleFunc("GET /api/sync", handlers.WithAPIKey(handlers.APISyncStatus))
	mux.HandleFunc("POST /api/sync/trigger", handlers.WithAPIKey(handlers.APISyncTrigger))

	mux.HandleFunc("/", http.NotFound)

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", handlers.AuthMiddleware(mux)))
}
