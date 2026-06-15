package handlers

import (
	"net/http"
	"time"

	"pi-webpage/db"
)

type workoutSetJSON struct {
	ID        int64    `json:"id"`
	Date      string   `json:"date"`
	ExerciseID int64   `json:"exercise_id"`
	Reps      int      `json:"reps"`
	WeightLbs *float64 `json:"weight_lbs"`
}

type workoutGroupJSON struct {
	ExerciseID     int64            `json:"exercise_id"`
	ExerciseName   string           `json:"exercise_name"`
	BodyPart       *string          `json:"body_part"`
	TotalVolumeLbs float64          `json:"total_volume_lbs"`
	Sets           []workoutSetJSON `json:"sets"`
}

type workoutSummaryJSON struct {
	TotalSets      int                `json:"total_sets"`
	TotalVolumeLbs float64            `json:"total_volume_lbs"`
	ExerciseCount  int                `json:"exercise_count"`
	Groups         []workoutGroupJSON `json:"groups"`
}

type daySnapshotJSON struct {
	Date      string          `json:"date"`
	System    *systemJSON     `json:"system"`
	Gym       *gymJSON        `json:"gym"`
	Nutrition *nutritionJSON  `json:"nutrition"`
	Health    *healthDayJSON  `json:"health"`
	Body      *bodyMetricJSON `json:"body"`
	Workout   *workoutSummaryJSON `json:"workout"`
}

type systemJSON struct {
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryPercent float64 `json:"memory_percent"`
	DiskPercent   float64 `json:"disk_percent"`
	TempCelsius   float64 `json:"temp_celsius"`
}

type gymJSON struct {
	Checkins []string `json:"checkins"`
}

type nutritionJSON struct {
	Calories      *float64 `json:"calories"`
	CalorieBudget *float64 `json:"calorie_budget"`
	ProteinG      *float64 `json:"protein_g"`
	CarbG         *float64 `json:"carb_g"`
	FatG          *float64 `json:"fat_g"`
	FibreG        *float64 `json:"fibre_g"`
}

type healthDayJSON struct {
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

type bodyMetricJSON struct {
	Date      string   `json:"date"`
	WeightLbs *float64 `json:"weight_lbs"`
	ChestMm   *float64 `json:"chest_mm"`
	AbdomenMm *float64 `json:"abdomen_mm"`
	ThighMm   *float64 `json:"thigh_mm"`
	BfPercent *float64 `json:"bf_percent"`
}

func toSetJSON(s db.WorkoutSet) workoutSetJSON {
	return workoutSetJSON{
		ID:         s.ID,
		Date:       s.Date,
		ExerciseID: s.ExerciseID,
		Reps:       s.Reps,
		WeightLbs:  nfPtr(s.WeightLbs),
	}
}

func toGroupsJSON(sets []db.WorkoutSet) []workoutGroupJSON {
	groups := groupSetsByExercise(sets)
	out := make([]workoutGroupJSON, 0, len(groups))
	for _, g := range groups {
		gj := workoutGroupJSON{
			ExerciseID:     g.ExerciseID,
			ExerciseName:   g.ExerciseName,
			TotalVolumeLbs: g.TotalVolume,
			Sets:           make([]workoutSetJSON, 0, len(g.Sets)),
		}
		if g.BodyPart != "" {
			bp := g.BodyPart
			gj.BodyPart = &bp
		}
		for _, s := range g.Sets {
			gj.Sets = append(gj.Sets, toSetJSON(s))
		}
		out = append(out, gj)
	}
	return out
}

func toHealthJSON(h db.HealthDay) *healthDayJSON {
	return &healthDayJSON{
		Date:           h.Date,
		Steps:          niPtr(h.Steps),
		ActiveCalories: nfPtr(h.ActiveCalories),
		RestingHR:      nfPtr(h.RestingHR),
		SleepAsleepH:   nfPtr(h.SleepAsleepH),
		SleepDeepH:     nfPtr(h.SleepDeepH),
		SleepRemH:      nfPtr(h.SleepRemH),
		SleepCoreH:     nfPtr(h.SleepCoreH),
		SleepAwakeH:    nfPtr(h.SleepAwakeH),
	}
}

func toBodyJSON(b db.BodyMetric) *bodyMetricJSON {
	return &bodyMetricJSON{
		Date:      b.Date,
		WeightLbs: nfPtr(b.WeightLbs),
		ChestMm:   nfPtr(b.ChestMm),
		AbdomenMm: nfPtr(b.AbdomenMm),
		ThighMm:   nfPtr(b.ThighMm),
		BfPercent: nfPtr(b.BfPercent),
	}
}

// buildDaySnapshot assembles the full snapshot for one date.
// System metrics are included only when the date is today.
func buildDaySnapshot(dateStr string) (daySnapshotJSON, error) {
	t, err := time.ParseInLocation("2006-01-02", dateStr, time.Local)
	if err != nil {
		return daySnapshotJSON{}, err
	}
	out := daySnapshotJSON{Date: dateStr}

	if dateStr == time.Now().Format("2006-01-02") {
		if s, err := collectStats(); err == nil {
			out.System = &systemJSON{
				CPUPercent:    s.CPUPercent,
				MemoryPercent: s.MemPercent,
				DiskPercent:   s.DiskPercent,
				TempCelsius:   s.TempCelsius,
			}
		}
	}

	from := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.Local)
	to := from.AddDate(0, 0, 1)
	if checkins, err := db.CheckinDatesBetween(from, to); err == nil {
		if times := checkins[dateStr]; len(times) > 0 {
			g := &gymJSON{}
			for _, c := range times {
				g.Checkins = append(g.Checkins, c.Format(time.RFC3339))
			}
			out.Gym = g
		}
	}
	if nutri, err := db.NutritionBetween(t, t); err == nil {
		if n, ok := nutri[dateStr]; ok {
			out.Nutrition = &nutritionJSON{
				Calories:      nfPtr(n.Calories),
				CalorieBudget: nfPtr(n.CalorieBudget),
				ProteinG:      nfPtr(n.ProteinG),
				CarbG:         nfPtr(n.CarbG),
				FatG:          nfPtr(n.FatG),
				FibreG:        nfPtr(n.FibreG),
			}
		}
	}
	if health, err := db.HealthBetween(t, t); err == nil {
		if h, ok := health[dateStr]; ok {
			out.Health = toHealthJSON(h)
		}
	}
	if body, err := db.BodyBetween(t, t); err == nil {
		if b, ok := body[dateStr]; ok {
			out.Body = toBodyJSON(b)
		}
	}
	sets, err := db.WorkoutSetsForDay(dateStr)
	if err == nil && len(sets) > 0 {
		ws := &workoutSummaryJSON{Groups: toGroupsJSON(sets)}
		for _, s := range sets {
			ws.TotalSets++
			if s.WeightLbs.Valid {
				ws.TotalVolumeLbs += s.WeightLbs.Float64 * float64(s.Reps)
			}
		}
		ws.ExerciseCount = len(ws.Groups)
		out.Workout = ws
	}
	return out, nil
}

// GET /api/today and GET /api/day?date=
func APIToday(w http.ResponseWriter, r *http.Request, _ *db.User) {
	dateStr := r.URL.Query().Get("date")
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	snap, err := buildDaySnapshot(dateStr)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "invalid date")
		return
	}
	writeJSON(w, http.StatusOK, snap)
}

// GET /api/calendar?view=month|week&date=YYYY-MM-DD
func APICalendar(w http.ResponseWriter, r *http.Request, _ *db.User) {
	view := r.URL.Query().Get("view")
	if view != "week" {
		view = "month"
	}
	anchor := parseAnchor(r.URL.Query().Get("date"))
	model, err := buildFitnessModel(view, anchor)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}

	type cellJSON struct {
		Date          string   `json:"date"`
		Day           int      `json:"day"`
		InPeriod      bool     `json:"in_period"`
		IsToday       bool     `json:"is_today"`
		HasGym        bool     `json:"has_gym"`
		HasWorkout    bool     `json:"has_workout"`
		HasWeight     bool     `json:"has_weight"`
		HasCalories   bool     `json:"has_calories"`
		Calories      *float64 `json:"calories"`
		CalorieBudget *float64 `json:"calorie_budget"`
		HasSteps      bool     `json:"has_steps"`
		Steps         *int64   `json:"steps"`
		HasSleep      bool     `json:"has_sleep"`
		SleepHours    *float64 `json:"sleep_hours"`
	}

	cells := make([]cellJSON, 0, len(model.Cells))
	workoutDays := 0
	var first, last string
	for _, c := range model.Cells {
		cj := cellJSON{
			Date:        c.Key,
			Day:         c.Day,
			InPeriod:    c.InMonth,
			IsToday:     c.IsToday,
			HasGym:      c.HasGym,
			HasWorkout:  c.HasWorkout,
			HasWeight:   c.HasWeight,
			HasCalories: c.HasCalories,
			HasSteps:    c.HasSteps,
			HasSleep:    c.HasSleep,
		}
		if c.HasCalories {
			v := c.Calories
			cj.Calories = &v
			if c.CalorieBudget > 0 {
				b := c.CalorieBudget
				cj.CalorieBudget = &b
			}
		}
		if c.HasSteps {
			v := c.Steps
			cj.Steps = &v
		}
		if c.HasSleep {
			v := c.SleepHours
			cj.SleepHours = &v
		}
		if c.InMonth && c.HasWorkout {
			workoutDays++
		}
		if first == "" {
			first = c.Key
		}
		last = c.Key
		cells = append(cells, cj)
	}

	// Total volume across the visible period
	var totalVolume float64
	if first != "" {
		fromT, _ := time.ParseInLocation("2006-01-02", first, time.Local)
		toT, _ := time.ParseInLocation("2006-01-02", last, time.Local)
		if sets, err := db.WorkoutSetsBetween(fromT, toT); err == nil {
			for _, s := range sets {
				if s.WeightLbs.Valid {
					totalVolume += s.WeightLbs.Float64 * float64(s.Reps)
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"view":      model.View,
		"label":     model.Label,
		"prev_date": model.PrevStr,
		"next_date": model.NextStr,
		"today":     model.TodayStr,
		"cells":     cells,
		"stats": map[string]any{
			"gym_days":         model.GymDays,
			"avg_calories":     model.AvgCalories,
			"avg_steps":        model.AvgSteps,
			"avg_sleep_h":      model.AvgSleep,
			"workout_days":     workoutDays,
			"total_volume_lbs": totalVolume,
		},
	})
}
