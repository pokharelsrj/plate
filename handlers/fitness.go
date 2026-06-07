package handlers

import (
	"net/http"
	"time"

	"pi-webpage/components"
	"pi-webpage/db"
)

func FitnessPage(w http.ResponseWriter, r *http.Request) {
	view := r.URL.Query().Get("view")
	if view != "week" {
		view = "month"
	}
	anchor := parseAnchor(r.URL.Query().Get("date"))

	model, err := buildFitnessModel(view, anchor)
	if err != nil {
		http.Error(w, "failed to load fitness data: "+err.Error(), http.StatusInternalServerError)
		return
	}
	components.FitnessPage(model).Render(r.Context(), w)
}

func FitnessGrid(w http.ResponseWriter, r *http.Request) {
	view := r.URL.Query().Get("view")
	if view != "week" {
		view = "month"
	}
	anchor := parseAnchor(r.URL.Query().Get("date"))
	model, err := buildFitnessModel(view, anchor)
	if err != nil {
		http.Error(w, "failed: "+err.Error(), http.StatusInternalServerError)
		return
	}
	components.FitnessGrid(model).Render(r.Context(), w)
}

func FitnessDayDetail(w http.ResponseWriter, r *http.Request) {
	dateStr := r.URL.Query().Get("date")
	t, err := time.ParseInLocation("2006-01-02", dateStr, time.Local)
	if err != nil {
		http.Error(w, "bad date", http.StatusBadRequest)
		return
	}
	from := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.Local)
	to := from.AddDate(0, 0, 1)
	checkins, _ := db.CheckinDatesBetween(from, to)
	nutri, _ := db.NutritionBetween(t, t)

	detail := components.DayDetail{
		Date:     t,
		Checkins: checkins[dateStr],
	}
	if n, ok := nutri[dateStr]; ok {
		detail.Nutrition = &n
	}
	components.DayDetailCard(detail).Render(r.Context(), w)
}

func parseAnchor(s string) time.Time {
	if s == "" {
		return time.Now()
	}
	if t, err := time.ParseInLocation("2006-01-02", s, time.Local); err == nil {
		return t
	}
	return time.Now()
}

func buildFitnessModel(view string, anchor time.Time) (components.FitnessModel, error) {
	var from, to time.Time
	if view == "week" {
		// Week containing anchor, Sunday start
		offset := int(anchor.Weekday())
		from = time.Date(anchor.Year(), anchor.Month(), anchor.Day()-offset, 0, 0, 0, 0, time.Local)
		to = from.AddDate(0, 0, 7)
	} else {
		first := time.Date(anchor.Year(), anchor.Month(), 1, 0, 0, 0, 0, time.Local)
		// Pad to start on Sunday
		offset := int(first.Weekday())
		from = first.AddDate(0, 0, -offset)
		// End: last day of month, padded to fill the week
		lastOfMonth := first.AddDate(0, 1, -1)
		endOffset := 6 - int(lastOfMonth.Weekday())
		to = lastOfMonth.AddDate(0, 0, endOffset+1)
	}
	checkins, err := db.CheckinDatesBetween(from, to)
	if err != nil {
		return components.FitnessModel{}, err
	}
	nutri, err := db.NutritionBetween(from, to.AddDate(0, 0, -1))
	if err != nil {
		return components.FitnessModel{}, err
	}

	today := time.Now().Format("2006-01-02")
	var cells []components.DayCell
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		cell := components.DayCell{
			Date:    d,
			Key:     key,
			Day:     d.Day(),
			InMonth: view == "week" || d.Month() == anchor.Month(),
			IsToday: key == today,
			HasGym:  len(checkins[key]) > 0,
		}
		if n, ok := nutri[key]; ok && n.Calories.Valid {
			cell.HasCalories = true
			cell.Calories = n.Calories.Float64
			if n.CalorieBudget.Valid {
				cell.CalorieBudget = n.CalorieBudget.Float64
			}
		}
		cells = append(cells, cell)
	}

	prev, next, label := navDates(view, anchor)
	return components.FitnessModel{
		View:      view,
		Anchor:    anchor,
		AnchorStr: anchor.Format("2006-01-02"),
		Label:     label,
		PrevStr:   prev,
		NextStr:   next,
		TodayStr:  time.Now().Format("2006-01-02"),
		Cells:     cells,
	}, nil
}

func navDates(view string, anchor time.Time) (prev, next, label string) {
	if view == "week" {
		prev = anchor.AddDate(0, 0, -7).Format("2006-01-02")
		next = anchor.AddDate(0, 0, 7).Format("2006-01-02")
		offset := int(anchor.Weekday())
		start := anchor.AddDate(0, 0, -offset)
		end := start.AddDate(0, 0, 6)
		label = start.Format("Jan 2") + " — " + end.Format("Jan 2, 2006")
		return
	}
	prev = anchor.AddDate(0, -1, 0).Format("2006-01-02")
	next = anchor.AddDate(0, 1, 0).Format("2006-01-02")
	label = anchor.Format("January 2006")
	return
}
