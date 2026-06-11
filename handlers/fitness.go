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
	health, _ := db.HealthBetween(t, t)
	body, _ := db.BodyBetween(t, t)

	detail := components.DayDetail{
		Date:     t,
		Checkins: checkins[dateStr],
	}
	if n, ok := nutri[dateStr]; ok {
		detail.Nutrition = &n
	}
	if h, ok := health[dateStr]; ok {
		detail.Health = &h
	}
	if bm, ok := body[dateStr]; ok {
		detail.Body = &bm
	}
	wsets, _ := db.WorkoutSetsForDay(dateStr)
	detail.WorkoutSets = wsets
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
	health, err := db.HealthBetween(from, to.AddDate(0, 0, -1))
	if err != nil {
		return components.FitnessModel{}, err
	}
	body, err := db.BodyBetween(from, to.AddDate(0, 0, -1))
	if err != nil {
		return components.FitnessModel{}, err
	}
	workoutDays, err := db.WorkoutDaysSet(from, to.AddDate(0, 0, -1))
	if err != nil {
		return components.FitnessModel{}, err
	}

	today := time.Now().Format("2006-01-02")
	var cells []components.DayCell
	var gymDays, stepsCount, sleepCount int
	var calTotal, stepsTotal, sleepTotal float64
	var calCount int
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		inPeriod := view == "week" || d.Month() == anchor.Month()
		cell := components.DayCell{
			Date:    d,
			Key:     key,
			Day:     d.Day(),
			InMonth: inPeriod,
			IsToday: key == today,
			HasGym:  len(checkins[key]) > 0,
		}
		if n, ok := nutri[key]; ok && n.Calories.Valid && n.Calories.Float64 > 0 {
			cell.HasCalories = true
			cell.Calories = n.Calories.Float64
			if n.CalorieBudget.Valid {
				cell.CalorieBudget = n.CalorieBudget.Float64
			}
		}
		if h, ok := health[key]; ok {
			if h.Steps.Valid && h.Steps.Int64 > 0 {
				cell.HasSteps = true
				cell.Steps = h.Steps.Int64
			}
			if h.SleepAsleepH.Valid && h.SleepAsleepH.Float64 > 0 {
				cell.HasSleep = true
				cell.SleepHours = h.SleepAsleepH.Float64
			}
		}
		if bm, ok := body[key]; ok {
			if bm.WeightLbs.Valid && bm.WeightLbs.Float64 > 0 {
				cell.HasWeight = true
				cell.Weight = bm.WeightLbs.Float64
			}
		}
		if workoutDays[key] {
			cell.HasWorkout = true
		}
		if inPeriod {
			if cell.HasGym {
				gymDays++
			}
			if cell.HasCalories {
				calTotal += cell.Calories
				calCount++
			}
			if cell.HasSteps {
				stepsTotal += float64(cell.Steps)
				stepsCount++
			}
			if cell.HasSleep {
				sleepTotal += cell.SleepHours
				sleepCount++
			}
		}
		cells = append(cells, cell)
	}

	avgCal := 0.0
	if calCount > 0 {
		avgCal = calTotal / float64(calCount)
	}
	avgSteps := 0.0
	if stepsCount > 0 {
		avgSteps = stepsTotal / float64(stepsCount)
	}
	avgSleep := 0.0
	if sleepCount > 0 {
		avgSleep = sleepTotal / float64(sleepCount)
	}
	periodLabel := "MONTH"
	if view == "week" {
		periodLabel = "WEEK"
	}

	prev, next, label := navDates(view, anchor)
	return components.FitnessModel{
		View:        view,
		Anchor:      anchor,
		AnchorStr:   anchor.Format("2006-01-02"),
		Label:       label,
		PrevStr:     prev,
		NextStr:     next,
		TodayStr:    time.Now().Format("2006-01-02"),
		Cells:       cells,
		GymDays:     gymDays,
		AvgCalories: avgCal,
		AvgSteps:    avgSteps,
		AvgSleep:    avgSleep,
		PeriodLabel: periodLabel,
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
