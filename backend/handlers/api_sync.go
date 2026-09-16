package handlers

import (
	"net/http"
	"strconv"
	"time"

	"plate/db"
	"plate/sync"
)

// GET /api/sync
func APISyncStatus(w http.ResponseWriter, r *http.Request, _ *db.User) {
	type sourceJSON struct {
		Name          string  `json:"name"`
		Running       bool    `json:"running"`
		PushBased     bool    `json:"push_based"`
		LastSuccessAt *string `json:"last_success_at"`
		LastRecords   *int    `json:"last_records"`
	}
	var sources []sourceJSON
	appendSource := func(name string, running, pushBased bool) {
		s := sourceJSON{Name: name, Running: running, PushBased: pushBased}
		if last, _ := db.LastSuccessfulSync(name); last != nil {
			at := last.StartedAt.UTC().Format(time.RFC3339)
			if last.CompletedAt.Valid {
				at = last.CompletedAt.Time.UTC().Format(time.RFC3339)
			}
			s.LastSuccessAt = &at
			rec := last.RecordsSynced
			s.LastRecords = &rec
		}
		sources = append(sources, s)
	}
	for _, src := range sync.Sources {
		appendSource(src.Name, sync.IsRunning(src.Name), false)
	}
	appendSource("apple_health", false, true)

	runs, _ := db.RecentSyncRuns(20)
	type runJSON struct {
		ID            int64   `json:"id"`
		Source        string  `json:"source"`
		StartedAt     string  `json:"started_at"`
		CompletedAt   *string `json:"completed_at"`
		Status        string  `json:"status"`
		RecordsSynced int     `json:"records_synced"`
		ErrorMessage  *string `json:"error_message"`
	}
	outRuns := make([]runJSON, 0, len(runs))
	for _, run := range runs {
		rj := runJSON{
			ID:            run.ID,
			Source:        run.Source,
			StartedAt:     run.StartedAt.UTC().Format(time.RFC3339),
			Status:        run.Status,
			RecordsSynced: run.RecordsSynced,
		}
		if run.CompletedAt.Valid {
			c := run.CompletedAt.Time.UTC().Format(time.RFC3339)
			rj.CompletedAt = &c
		}
		if run.ErrorMessage.Valid {
			e := run.ErrorMessage.String
			rj.ErrorMessage = &e
		}
		outRuns = append(outRuns, rj)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"sources":     sources,
		"recent_runs": outRuns,
	})
}

// POST /api/sync/trigger?source=lafitness&days=60
func APISyncTrigger(w http.ResponseWriter, r *http.Request, _ *db.User) {
	src := r.URL.Query().Get("source")
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if !sync.TriggerManual(src, days) {
		apiErr(w, http.StatusBadRequest, "unknown source")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"triggered": src})
}
