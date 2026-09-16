package handlers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"

	"plate/db"
)

type healthDayIn struct {
	Date           string   `json:"date"`
	Steps          *int64   `json:"steps"`
	ActiveCalories *float64 `json:"active_calories"`
	RestingHR      *float64 `json:"resting_hr"`
	SleepAsleepH   *float64 `json:"sleep_asleep_h"`
	SleepDeepH     *float64 `json:"sleep_deep_h"`
	SleepRemH      *float64 `json:"sleep_rem_h"`
	SleepCoreH     *float64 `json:"sleep_core_h"`
	SleepAwakeH    *float64 `json:"sleep_awake_h"`
}

type healthIngestReq struct {
	Days []healthDayIn `json:"days"`
}

func HealthIngest(w http.ResponseWriter, r *http.Request) {
	// Any active user's API key works, and apiUser also maps the legacy
	// HEALTH_API_KEY onto the seeded admin. The days are filed against
	// whichever account the key belongs to, so two people can each point a
	// Shortcut here without their data mixing.
	u := apiUser(r)
	if u == nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var req healthIngestReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad json: "+err.Error(), http.StatusBadRequest)
		return
	}
	if len(req.Days) == 0 {
		http.Error(w, "empty days", http.StatusBadRequest)
		return
	}

	id, _ := db.StartSyncRun(u.ID, "apple_health")
	count := 0
	var firstErr error
	for _, d := range req.Days {
		if d.Date == "" {
			continue
		}
		h := db.HealthDay{
			Date:           d.Date,
			Steps:          nullInt(d.Steps),
			ActiveCalories: nullFloat(d.ActiveCalories),
			RestingHR:      nullFloat(d.RestingHR),
			SleepAsleepH:   nullFloat(d.SleepAsleepH),
			SleepDeepH:     nullFloat(d.SleepDeepH),
			SleepRemH:      nullFloat(d.SleepRemH),
			SleepCoreH:     nullFloat(d.SleepCoreH),
			SleepAwakeH:    nullFloat(d.SleepAwakeH),
		}
		if err := db.UpsertHealthDay(u.ID, h); err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("upsert %s: %w", d.Date, err)
			}
			continue
		}
		count++
	}
	_ = db.FinishSyncRun(id, count, firstErr)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"received": len(req.Days),
		"stored":   count,
	})
}

func nullInt(p *int64) sql.NullInt64 {
	if p == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: *p, Valid: true}
}

func nullFloat(p *float64) sql.NullFloat64 {
	if p == nil {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: *p, Valid: true}
}
