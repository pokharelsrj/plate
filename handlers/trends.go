package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"pi-webpage/components"
	"pi-webpage/db"
)

func TrendsPage(w http.ResponseWriter, r *http.Request) {
	components.TrendsPage(parseRange(r)).Render(r.Context(), w)
}

func TrendsData(w http.ResponseWriter, r *http.Request) {
	days := parseRange(r)
	to := time.Now()
	from := to.AddDate(0, 0, -days+1)

	checkins, _ := db.CheckinDatesBetween(
		time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, time.Local),
		to.AddDate(0, 0, 1),
	)
	nutri, _ := db.NutritionBetween(from, to)

	type point struct {
		Date     string   `json:"date"`
		Calories *float64 `json:"calories"`
		Protein  *float64 `json:"protein"`
		Carb     *float64 `json:"carb"`
		Fat      *float64 `json:"fat"`
		Fibre    *float64 `json:"fibre"`
		Gym      bool     `json:"gym"`
	}
	var pts []point
	var calBudget float64
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		p := point{Date: key, Gym: len(checkins[key]) > 0}
		if n, ok := nutri[key]; ok {
			if n.Calories.Valid {
				v := n.Calories.Float64
				p.Calories = &v
			}
			if n.ProteinG.Valid {
				v := n.ProteinG.Float64
				p.Protein = &v
			}
			if n.CarbG.Valid {
				v := n.CarbG.Float64
				p.Carb = &v
			}
			if n.FatG.Valid {
				v := n.FatG.Float64
				p.Fat = &v
			}
			if n.FibreG.Valid {
				v := n.FibreG.Float64
				p.Fibre = &v
			}
			if n.CalorieBudget.Valid && calBudget == 0 {
				calBudget = n.CalorieBudget.Float64
			}
		}
		pts = append(pts, p)
	}

	// Summary stats
	var calTotal, calCount, gymCount float64
	for _, p := range pts {
		if p.Calories != nil {
			calTotal += *p.Calories
			calCount++
		}
		if p.Gym {
			gymCount++
		}
	}
	avgCal := 0.0
	if calCount > 0 {
		avgCal = calTotal / calCount
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"points":         pts,
		"calorie_budget": calBudget,
		"avg_calories":   avgCal,
		"gym_days":       gymCount,
		"range_days":     days,
	})
}

func parseRange(r *http.Request) int {
	s := r.URL.Query().Get("range")
	if s == "" {
		return 30
	}
	n, err := strconv.Atoi(s)
	if err != nil || n <= 0 || n > 365 {
		return 30
	}
	return n
}
