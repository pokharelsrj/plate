package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"pi-webpage/components"
	"pi-webpage/db"
)

// bodyParts returns the current list of tag names. Cached per request via the DB.
func bodyParts() []string {
	bp, _ := db.ListBodyParts()
	return bp
}

func WorkoutPage(w http.ResponseWriter, r *http.Request) {
	renderWorkoutPage(w, r, "")
}

func WorkoutAddSet(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		renderWorkoutPage(w, r, "bad form data")
		return
	}

	dateStr := strings.TrimSpace(r.FormValue("date"))
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", dateStr); err != nil {
		renderWorkoutPage(w, r, "invalid date")
		return
	}

	exerciseID, err := strconv.ParseInt(r.FormValue("exercise_id"), 10, 64)
	if err != nil || exerciseID <= 0 {
		renderWorkoutPage(w, r, "select an exercise")
		return
	}
	reps, err := strconv.Atoi(strings.TrimSpace(r.FormValue("reps")))
	if err != nil || reps <= 0 || reps > 1000 {
		renderWorkoutPage(w, r, "reps must be a positive number")
		return
	}
	weight := parseNullFloat(r.FormValue("weight_lbs"))

	if err := db.AddWorkoutSet(dateStr, exerciseID, reps, weight); err != nil {
		renderWorkoutPage(w, r, "save failed: "+err.Error())
		return
	}
	// Preserve date and exercise selection across redirects
	q := r.URL.Query()
	q.Set("date", dateStr)
	q.Set("exercise_id", strconv.FormatInt(exerciseID, 10))
	http.Redirect(w, r, "/workout?"+q.Encode(), http.StatusSeeOther)
}

func WorkoutUpdateSet(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	id, err := strconv.ParseInt(r.FormValue("set_id"), 10, 64)
	if err != nil {
		http.Error(w, "bad id", http.StatusBadRequest)
		return
	}
	reps, err := strconv.Atoi(strings.TrimSpace(r.FormValue("reps")))
	if err != nil || reps <= 0 || reps > 1000 {
		http.Error(w, "reps must be a positive number", http.StatusBadRequest)
		return
	}
	weight := parseNullFloat(r.FormValue("weight_lbs"))
	if err := db.UpdateWorkoutSet(id, reps, weight); err != nil {
		http.Error(w, "update failed", http.StatusInternalServerError)
		return
	}
	dateStr := r.FormValue("date")
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	q := "?date=" + dateStr
	if eid := r.FormValue("exercise_id"); eid != "" {
		q += "&exercise_id=" + eid
	}
	http.Redirect(w, r, "/workout"+q, http.StatusSeeOther)
}

func WorkoutDeleteSet(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	id, err := strconv.ParseInt(r.FormValue("set_id"), 10, 64)
	if err != nil {
		http.Error(w, "bad id", http.StatusBadRequest)
		return
	}
	if err := db.DeleteWorkoutSet(id); err != nil {
		http.Error(w, "delete failed", http.StatusInternalServerError)
		return
	}
	dateStr := r.FormValue("date")
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	http.Redirect(w, r, "/workout?date="+dateStr, http.StatusSeeOther)
}

func renderWorkoutPage(w http.ResponseWriter, r *http.Request, errMsg string) {
	dateStr := r.URL.Query().Get("date")
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", dateStr); err != nil {
		dateStr = time.Now().Format("2006-01-02")
	}

	exercises, _ := db.ListExercises()
	sets, _ := db.WorkoutSetsForDay(dateStr)

	var selectedID int64
	if s := r.URL.Query().Get("exercise_id"); s != "" {
		selectedID, _ = strconv.ParseInt(s, 10, 64)
	}

	// Group exercises by body part for the picker
	pickerGroups := groupExercisesByBodyPart(exercises)

	// Group today's sets by exercise
	todayGroups := groupSetsByExercise(sets)

	// Build active-exercise panel data
	var active *components.WorkoutActive
	if selectedID > 0 {
		var ex *db.Exercise
		for i := range exercises {
			if exercises[i].ID == selectedID {
				ex = &exercises[i]
				break
			}
		}
		if ex != nil {
			active = &components.WorkoutActive{
				ExerciseID:   ex.ID,
				ExerciseName: ex.Name,
			}
			if ex.BodyPart.Valid {
				active.BodyPart = ex.BodyPart.String
			}
			// Today's sets for active
			var todayActive []db.WorkoutSet
			var todayVol float64
			for _, g := range todayGroups {
				if g.ExerciseID == selectedID {
					todayActive = g.Sets
					todayVol = g.TotalVolume
					break
				}
			}
			active.TodaySets = todayActive
			active.TodayVolume = todayVol

			// Prefill: most recent set's values (today's last set, or last session's last set)
			if last, _ := db.LastSetForExercise(selectedID); last != nil {
				active.PrefillReps = last.Reps
				if last.WeightLbs.Valid {
					active.PrefillWeight = last.WeightLbs.Float64
				}
			}

			// Last session reference (excluding today)
			if lastSession, _ := db.LastSessionForExercise(selectedID, dateStr); len(lastSession) > 0 {
				active.LastSessionDate = lastSession[0].Date
				active.LastSessionSets = lastSession
			}
		}
	}

	// Compute session totals
	var totalSets int
	var totalVol float64
	for _, s := range sets {
		totalSets++
		if s.WeightLbs.Valid {
			totalVol += s.WeightLbs.Float64 * float64(s.Reps)
		}
	}

	prev := dateOffset(dateStr, -1)
	next := dateOffset(dateStr, 1)

	model := components.WorkoutPageModel{
		Date:          dateStr,
		PrevDate:      prev,
		NextDate:      next,
		Today:         time.Now().Format("2006-01-02"),
		Exercises:     exercises,
		SelectedID:    selectedID,
		BodyParts:     bodyParts(),
		PickerGroups:  pickerGroups,
		Active:        active,
		Groups:        todayGroups,
		TotalSets:     totalSets,
		TotalVolume:   totalVol,
		ExerciseCount: len(todayGroups),
		ErrorMsg:      errMsg,
	}
	components.WorkoutPage(model).Render(r.Context(), w)
}

func groupExercisesByBodyPart(exs []db.Exercise) []components.PickerGroup {
	order := append([]string{}, bodyParts()...)
	order = append(order, "") // uncategorized last
	bucket := map[string][]db.Exercise{}
	for _, e := range exs {
		k := ""
		if e.BodyPart.Valid {
			k = e.BodyPart.String
		}
		bucket[k] = append(bucket[k], e)
	}
	seen := map[string]bool{}
	out := make([]components.PickerGroup, 0, len(order))
	for _, k := range order {
		if seen[k] {
			continue
		}
		seen[k] = true
		if items, ok := bucket[k]; ok {
			label := k
			if label == "" {
				label = "uncategorized"
			}
			out = append(out, components.PickerGroup{BodyPart: label, Exercises: items})
		}
	}
	// Catch any body part not in the master list (e.g., stale tag)
	for k, items := range bucket {
		if seen[k] {
			continue
		}
		out = append(out, components.PickerGroup{BodyPart: k, Exercises: items})
	}
	return out
}

func groupSetsByExercise(sets []db.WorkoutSet) []components.WorkoutGroup {
	type bucket struct {
		ExerciseName string
		BodyPart     string
		Sets         []db.WorkoutSet
	}
	m := map[int64]*bucket{}
	var order []int64
	for _, s := range sets {
		b, ok := m[s.ExerciseID]
		if !ok {
			bp := ""
			if s.BodyPart.Valid {
				bp = s.BodyPart.String
			}
			b = &bucket{ExerciseName: s.ExerciseName, BodyPart: bp}
			m[s.ExerciseID] = b
			order = append(order, s.ExerciseID)
		}
		b.Sets = append(b.Sets, s)
	}
	out := make([]components.WorkoutGroup, 0, len(order))
	for _, id := range order {
		b := m[id]
		var totalVolume float64
		for _, s := range b.Sets {
			if s.WeightLbs.Valid {
				totalVolume += s.WeightLbs.Float64 * float64(s.Reps)
			}
		}
		out = append(out, components.WorkoutGroup{
			ExerciseID:   id,
			ExerciseName: b.ExerciseName,
			BodyPart:     b.BodyPart,
			Sets:         b.Sets,
			TotalVolume:  totalVolume,
		})
	}
	return out
}

func dateOffset(s string, days int) string {
	t, err := time.Parse("2006-01-02", s)
	if err != nil {
		return s
	}
	return t.AddDate(0, 0, days).Format("2006-01-02")
}
