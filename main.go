package main

import (
	"log"
	"net/http"

	"pi-webpage/handlers"
)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /login", handlers.LoginPage)
	mux.HandleFunc("POST /login", handlers.LoginSubmit)
	mux.HandleFunc("POST /logout", handlers.Logout)
	mux.HandleFunc("GET /", handlers.StatsPage)
	mux.HandleFunc("GET /stats/data", handlers.StatsData)

	log.Println("listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", handlers.AuthMiddleware(mux)))
}
