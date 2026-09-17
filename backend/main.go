package main

import (
	"log"
	"net/http"
	"os"

	"plate/db"
	"plate/handlers"
	"plate/sync"
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

	// Unauthenticated: sign-in and a liveness probe.
	mux.HandleFunc("POST /api/auth/login", handlers.APILogin)
	mux.HandleFunc("POST /api/auth/signup", handlers.APISignup)
	mux.HandleFunc("GET /api/health/ping", handlers.APIPing)

	// Apple Health ingestion — carries its own X-Api-Key check, because the
	// iOS Shortcut posts here from outside the LAN.
	mux.HandleFunc("POST /api/health/ingest", handlers.HealthIngest)

	// Everything below is X-Api-Key authenticated; WithAdmin also requires
	// the admin role.
	mux.HandleFunc("GET /api/me", handlers.WithAPIKey(handlers.APIMe))
	mux.HandleFunc("PUT /api/me", handlers.WithAPIKey(handlers.APIMeUpdate))
	mux.HandleFunc("PUT /api/me/password", handlers.WithAPIKey(handlers.APIMePassword))
	mux.HandleFunc("DELETE /api/me", handlers.WithAPIKey(handlers.APIMeDelete))

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
	log.Fatal(http.ListenAndServe(":8080", mux))
}
