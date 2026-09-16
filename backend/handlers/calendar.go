package handlers

import (
	"time"

	"plate/db"
)

// dayCell is one square on the calendar: the flags say what was logged that
// day, the values carry the numbers worth showing.
type dayCell struct {
	Key           string
	Day           int
	InPeriod      bool // false for the padding days of a neighbouring month
	IsToday       bool
	HasGym        bool
	HasWorkout    bool
	HasWeight     bool
	HasCalories   bool
	Calories      float64
	CalorieBudget float64
	HasSteps      bool
	Steps         int64
	HasSleep      bool
	SleepHours    float64
}

// calendarModel is one visible month or week, plus its period averages.
type calendarModel struct {
	View        string // "month" | "week"
	Label       string
	PrevStr     string
	NextStr     string
	TodayStr    string
	Cells       []dayCell
	GymDays     int
	AvgCalories float64
	AvgSteps    float64
	AvgSleep    float64
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

func buildCalendar(userID int64, view string, anchor time.Time) (calendarModel, error) {
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
	checkins, err := db.CheckinDatesBetween(userID, from, to)
	if err != nil {
		return calendarModel{}, err
	}
	nutri, err := db.NutritionBetween(userID, from, to.AddDate(0, 0, -1))
	if err != nil {
		return calendarModel{}, err
	}
	health, err := db.HealthBetween(userID, from, to.AddDate(0, 0, -1))
	if err != nil {
		return calendarModel{}, err
	}
	body, err := db.BodyBetween(userID, from, to.AddDate(0, 0, -1))
	if err != nil {
		return calendarModel{}, err
	}
	workoutDays, err := db.WorkoutDaysSet(userID, from, to.AddDate(0, 0, -1))
	if err != nil {
		return calendarModel{}, err
	}

	today := time.Now().Format("2006-01-02")
	var cells []dayCell
	var gymDays, stepsCount, sleepCount int
	var calTotal, stepsTotal, sleepTotal float64
	var calCount int
	for d := from; d.Before(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		inPeriod := view == "week" || d.Month() == anchor.Month()
		cell := dayCell{
			Key:      key,
			Day:      d.Day(),
			InPeriod: inPeriod,
			IsToday:  key == today,
			HasGym:   len(checkins[key]) > 0,
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
	prev, next, label := navDates(view, anchor)
	return calendarModel{
		View:        view,
		Label:       label,
		PrevStr:     prev,
		NextStr:     next,
		TodayStr:    time.Now().Format("2006-01-02"),
		Cells:       cells,
		GymDays:     gymDays,
		AvgCalories: avgCal,
		AvgSteps:    avgSteps,
		AvgSleep:    avgSleep,
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
