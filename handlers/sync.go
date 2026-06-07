package handlers

import (
	"net/http"
	"strconv"

	"pi-webpage/components"
	"pi-webpage/db"
	"pi-webpage/sync"
)

func SyncStatusPage(w http.ResponseWriter, r *http.Request) {
	model := buildSyncModel()
	components.SyncStatusPage(model).Render(r.Context(), w)
}

func SyncStatusFragment(w http.ResponseWriter, r *http.Request) {
	model := buildSyncModel()
	components.SyncStatusFragment(model).Render(r.Context(), w)
}

func SyncTrigger(w http.ResponseWriter, r *http.Request) {
	src := r.URL.Query().Get("source")
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if !sync.TriggerManual(src, days) {
		http.Error(w, "unknown source", http.StatusBadRequest)
		return
	}
	model := buildSyncModel()
	components.SyncStatusFragment(model).Render(r.Context(), w)
}

func buildSyncModel() components.SyncStatusModel {
	runs, _ := db.RecentSyncRuns(20)
	m := components.SyncStatusModel{Runs: runs}
	for _, s := range sync.Sources {
		latest, _ := db.LastSuccessfulSync(s.Name)
		m.Sources = append(m.Sources, components.SyncSourceStatus{
			Name:    s.Name,
			Last:    latest,
			Running: sync.IsRunning(s.Name),
		})
	}
	return m
}
