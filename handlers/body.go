package handlers

import (
	"database/sql"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"pi-webpage/components"
	"pi-webpage/db"
)

func BodyPage(w http.ResponseWriter, r *http.Request) {
	renderBodyPage(w, r, "", "")
}

func BodySubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderBodyPage(w, r, "", "bad form data")
		return
	}

	dateStr := strings.TrimSpace(r.FormValue("date"))
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	if _, err := time.ParseInLocation("2006-01-02", dateStr, time.Local); err != nil {
		renderBodyPage(w, r, "", "invalid date format (use YYYY-MM-DD)")
		return
	}

	b := db.BodyMetric{Date: dateStr}
	b.WeightLbs = parseNullFloat(r.FormValue("weight_lbs"))
	b.ChestMm = parseNullFloat(r.FormValue("chest_mm"))
	b.AbdomenMm = parseNullFloat(r.FormValue("abdomen_mm"))
	b.ThighMm = parseNullFloat(r.FormValue("thigh_mm"))

	if !b.WeightLbs.Valid && !b.ChestMm.Valid && !b.AbdomenMm.Valid && !b.ThighMm.Valid {
		renderBodyPage(w, r, "", "enter at least one value")
		return
	}

	// Compute BF% from Jackson-Pollock 3-site if all 3 calipers provided
	if b.ChestMm.Valid && b.AbdomenMm.Valid && b.ThighMm.Valid {
		age := computeAge(dateStr)
		if age > 0 {
			bf := jacksonPollock3Site(age, b.ChestMm.Float64, b.AbdomenMm.Float64, b.ThighMm.Float64)
			b.BfPercent = sql.NullFloat64{Float64: bf, Valid: true}
		}
	}

	if err := db.UpsertBodyMetric(b); err != nil {
		renderBodyPage(w, r, "", "save failed: "+err.Error())
		return
	}
	http.Redirect(w, r, "/body?ok=1", http.StatusSeeOther)
}

func renderBodyPage(w http.ResponseWriter, r *http.Request, _ /*ok*/ string, errMsg string) {
	history, _ := db.RecentBodyMetrics(60)

	model := components.BodyPageModel{
		Today:    time.Now().Format("2006-01-02"),
		History:  history,
		ErrorMsg: errMsg,
		OkMsg:    r.URL.Query().Get("ok"),
		HasDOB:   os.Getenv("USER_DOB") != "",
	}
	components.BodyPage(model).Render(r.Context(), w)
}

func parseNullFloat(s string) sql.NullFloat64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return sql.NullFloat64{}
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || f <= 0 {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: f, Valid: true}
}

func computeAge(refDateStr string) int {
	dob := os.Getenv("USER_DOB")
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

// jacksonPollock3Site returns body fat % using the Jackson-Pollock 3-site formula for men
// (chest, abdomen, thigh). All measurements in mm.
func jacksonPollock3Site(age int, chest, abdomen, thigh float64) float64 {
	sum := chest + abdomen + thigh
	db := 1.10938 - 0.0008267*sum + 0.0000016*sum*sum - 0.0002574*float64(age)
	if db <= 0 {
		return 0
	}
	return 495.0/db - 450.0
}
