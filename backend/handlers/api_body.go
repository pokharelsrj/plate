package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"time"

	"plate/db"
)

// GET /api/body?days=60
func APIBody(w http.ResponseWriter, r *http.Request, u *db.User) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 {
		days = 60
	}
	history, err := db.RecentBodyMetrics(u.ID, days)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out := make([]*bodyMetricJSON, 0, len(history))
	var latestWeight, latestBF *float64
	for _, b := range history {
		out = append(out, toBodyJSON(b))
		if latestWeight == nil && b.WeightLbs.Valid {
			latestWeight = nfPtr(b.WeightLbs)
		}
		if latestBF == nil && b.BfPercent.Valid {
			latestBF = nfPtr(b.BfPercent)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"history":           out,
		"latest_weight_lbs": latestWeight,
		"latest_bf_percent": latestBF,
	})
}

// POST /api/body
func APIBodySubmit(w http.ResponseWriter, r *http.Request, u *db.User) {
	var req struct {
		Date      string   `json:"date"`
		WeightLbs *float64 `json:"weight_lbs"`
		ChestMm   *float64 `json:"chest_mm"`
		AbdomenMm *float64 `json:"abdomen_mm"`
		ThighMm   *float64 `json:"thigh_mm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	if req.Date == "" {
		req.Date = time.Now().Format("2006-01-02")
	}
	if _, err := time.ParseInLocation("2006-01-02", req.Date, time.Local); err != nil {
		apiErr(w, http.StatusBadRequest, "invalid date")
		return
	}

	b := db.BodyMetric{Date: req.Date}
	b.WeightLbs = posFloat(req.WeightLbs)
	b.ChestMm = posFloat(req.ChestMm)
	b.AbdomenMm = posFloat(req.AbdomenMm)
	b.ThighMm = posFloat(req.ThighMm)

	if !b.WeightLbs.Valid && !b.ChestMm.Valid && !b.AbdomenMm.Valid && !b.ThighMm.Valid {
		apiErr(w, http.StatusBadRequest, "enter at least one value")
		return
	}

	if b.ChestMm.Valid && b.AbdomenMm.Valid && b.ThighMm.Valid {
		if age := ageForUser(u, req.Date); age > 0 {
			bf := jacksonPollock3Site(age, b.ChestMm.Float64, b.AbdomenMm.Float64, b.ThighMm.Float64)
			b.BfPercent = sql.NullFloat64{Float64: bf, Valid: true}
		}
	}

	if err := db.UpsertBodyMetric(u.ID, b); err != nil {
		apiErr(w, http.StatusInternalServerError, "save failed: "+err.Error())
		return
	}
	// Return the stored record (upsert may have merged with existing fields)
	t, _ := time.ParseInLocation("2006-01-02", req.Date, time.Local)
	stored, _ := db.BodyBetween(u.ID, t, t)
	if rec, ok := stored[req.Date]; ok {
		writeJSON(w, http.StatusOK, toBodyJSON(rec))
		return
	}
	writeJSON(w, http.StatusOK, toBodyJSON(b))
}

func posFloat(p *float64) sql.NullFloat64 {
	if p == nil || *p <= 0 {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: *p, Valid: true}
}

// ageForUser prefers the user's stored DOB, falling back to the USER_DOB env var.
func ageForUser(u *db.User, refDateStr string) int {
	dob := os.Getenv("USER_DOB")
	if u != nil && u.DateOfBirth.Valid && u.DateOfBirth.String != "" {
		dob = u.DateOfBirth.String
	}
	if dob == "" {
		return 0
	}
	dobT, err := time.ParseInLocation("2006-01-02", dob, time.Local)
	if err != nil {
		return 0
	}
	ref, err := time.ParseInLocation("2006-01-02", refDateStr, time.Local)
	if err != nil {
		ref = time.Now()
	}
	years := ref.Year() - dobT.Year()
	if ref.Month() < dobT.Month() || (ref.Month() == dobT.Month() && ref.Day() < dobT.Day()) {
		years--
	}
	if years < 0 {
		return 0
	}
	return years
}
