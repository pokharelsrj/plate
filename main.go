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

	sync.StartScheduler()
	sync.MaybeInitialBackfill()

	mux := http.NewServeMux()

	// Auth
	mux.HandleFunc("GET /login", handlers.LoginPage)
	mux.HandleFunc("POST /login", handlers.LoginSubmit)
	mux.HandleFunc("POST /logout", handlers.Logout)

	// Stats (system metrics)
	mux.HandleFunc("GET /", handlers.StatsPage)
	mux.HandleFunc("GET /stats/data", handlers.StatsData)

	// Fitness
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

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", handlers.AuthMiddleware(mux)))
}
