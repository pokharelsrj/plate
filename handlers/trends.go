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
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(buildTrendsPayload(parseRange(r)))
}

// APITrends serves the same payload over the X-Api-Key API for the iOS app.
func APITrends(w http.ResponseWriter, r *http.Request, _ *db.User) {
	writeJSON(w, http.StatusOK, buildTrendsPayload(parseRange(r)))
}

func buildTrendsPayload(days int) map[string]any {
	to := time.Now()
	from := to.AddDate(0, 0, -days+1)

	checkins, _ := db.CheckinDatesBetween(
		time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, time.Local),
		to.AddDate(0, 0, 1),
	)
	nutri, _ := db.NutritionBetween(from, to)
	health, _ := db.HealthBetween(from, to)
	body, _ := db.BodyBetween(from, to)
	workoutSets, _ := db.WorkoutSetsBetween(from, to)

	// Group workout volume by date and by body part
	volByDate := map[string]float64{}
	setsByBodyPart := map[string]int{}
	workoutDates := map[string]bool{}
	for _, s := range workoutSets {
		workoutDates[s.Date] = true
		if s.WeightLbs.Valid {
			volByDate[s.Date] += s.WeightLbs.Float64 * float64(s.Reps)
		}
		bp := "other"
		if s.BodyPart.Valid && s.BodyPart.String != "" {
			bp = s.BodyPart.String
		}
		setsByBodyPart[bp]++
	}

	type point struct {
		Date           string   `json:"date"`
		Calories       *float64 `json:"calories"`
		Protein        *float64 `json:"protein"`
		Carb           *float64 `json:"carb"`
		Fat            *float64 `json:"fat"`
		Fibre          *float64 `json:"fibre"`
		Gym            bool     `json:"gym"`
		Steps          *int64   `json:"steps"`
		ActiveCalories *float64 `json:"active_calories"`
		RestingHR      *float64 `json:"resting_hr"`
		SleepAsleep    *float64 `json:"sleep_asleep"`
		SleepDeep      *float64 `json:"sleep_deep"`
		SleepRem       *float64 `json:"sleep_rem"`
		SleepCore      *float64 `json:"sleep_core"`
		SleepAwake     *float64 `json:"sleep_awake"`
		WeightLbs      *float64 `json:"weight_lbs"`
		BfPercent      *float64 `json:"bf_percent"`
		WorkoutVolume  *float64 `json:"workout_volume"`
		HasWorkout     bool     `json:"has_workout"`
	}
	var pts []point
	var calBudget float64
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		p := point{Date: key, Gym: len(checkins[key]) > 0}
		if n, ok := nutri[key]; ok {
			if n.Calories.Valid && n.Calories.Float64 > 0 {
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
		if h, ok := health[key]; ok {
			if h.Steps.Valid {
				v := h.Steps.Int64
				p.Steps = &v
			}
			if h.ActiveCalories.Valid {
				v := h.ActiveCalories.Float64
				p.ActiveCalories = &v
			}
			if h.RestingHR.Valid {
				v := h.RestingHR.Float64
				p.RestingHR = &v
			}
			if h.SleepAsleepH.Valid {
				v := h.SleepAsleepH.Float64
				p.SleepAsleep = &v
			}
			if h.SleepDeepH.Valid {
				v := h.SleepDeepH.Float64
				p.SleepDeep = &v
			}
			if h.SleepRemH.Valid {
				v := h.SleepRemH.Float64
				p.SleepRem = &v
			}
			if h.SleepCoreH.Valid {
				v := h.SleepCoreH.Float64
				p.SleepCore = &v
			}
			if h.SleepAwakeH.Valid {
				v := h.SleepAwakeH.Float64
				p.SleepAwake = &v
			}
		}
		if b, ok := body[key]; ok {
			if b.WeightLbs.Valid {
				v := b.WeightLbs.Float64
				p.WeightLbs = &v
			}
			if b.BfPercent.Valid {
				v := b.BfPercent.Float64
				p.BfPercent = &v
			}
		}
		if v, ok := volByDate[key]; ok {
			p.WorkoutVolume = &v
		}
		if workoutDates[key] {
			p.HasWorkout = true
		}
		pts = append(pts, p)
	}

	// Summary stats
	var calTotal, calCount, gymCount, stepsTotal, stepsCount, sleepTotal, sleepCount float64
	var latestWeight, latestBF *float64
	for _, p := range pts {
		if p.Calories != nil {
			calTotal += *p.Calories
			calCount++
		}
		if p.Gym {
			gymCount++
		}
		if p.Steps != nil {
			stepsTotal += float64(*p.Steps)
			stepsCount++
		}
		if p.SleepAsleep != nil && *p.SleepAsleep > 0 {
			sleepTotal += *p.SleepAsleep
			sleepCount++
		}
		if p.WeightLbs != nil {
			v := *p.WeightLbs
			latestWeight = &v
		}
		if p.BfPercent != nil {
			v := *p.BfPercent
			latestBF = &v
		}
	}
	avgCal := 0.0
	if calCount > 0 {
		avgCal = calTotal / calCount
	}
	avgSteps := 0.0
	if stepsCount > 0 {
		avgSteps = stepsTotal / stepsCount
	}
	avgSleep := 0.0
	if sleepCount > 0 {
		avgSleep = sleepTotal / sleepCount
	}

	return map[string]any{
		"points":            pts,
		"calorie_budget":    calBudget,
		"avg_calories":      avgCal,
		"gym_days":          gymCount,
		"avg_steps":         avgSteps,
		"avg_sleep":         avgSleep,
		"latest_weight":     latestWeight,
		"latest_bf":         latestBF,
		"workout_days":      len(workoutDates),
		"total_volume":      totalWorkoutVolume(volByDate),
		"sets_by_body_part": setsByBodyPart,
		"range_days":        days,
	}
}

func totalWorkoutVolume(m map[string]float64) float64 {
	var t float64
	for _, v := range m {
		t += v
	}
	return t
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
