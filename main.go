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

	// Trends
	mux.HandleFunc("GET /trends", handlers.TrendsPage)
	mux.HandleFunc("GET /trends/data", handlers.TrendsData)

	// Sync status
	mux.HandleFunc("GET /sync", handlers.SyncStatusPage)
	mux.HandleFunc("GET /sync/status/fragment", handlers.SyncStatusFragment)
	mux.HandleFunc("POST /sync/trigger", handlers.SyncTrigger)

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", handlers.AuthMiddleware(mux)))
}
