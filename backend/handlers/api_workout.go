package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"plate/db"
)

// GET /api/workout?date=YYYY-MM-DD&exercise_id={id}
func APIWorkout(w http.ResponseWriter, r *http.Request, u *db.User) {
	dateStr := r.URL.Query().Get("date")
	if dateStr == "" {
		dateStr = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", dateStr); err != nil {
		apiErr(w, http.StatusBadRequest, "invalid date")
		return
	}
	sets, err := db.WorkoutSetsForDay(u.ID, dateStr)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}

	groups := toGroupsJSON(sets)

	resp := map[string]any{
		"date":           dateStr,
		"total_sets":     len(sets),
		"exercise_count": len(groups),
		"groups":         groups,
	}

	if eidStr := r.URL.Query().Get("exercise_id"); eidStr != "" {
		eid, err := strconv.ParseInt(eidStr, 10, 64)
		if err != nil || eid <= 0 {
			apiErr(w, http.StatusBadRequest, "bad exercise_id")
			return
		}
		exercises, _ := db.ListExercises()
		var ex *db.Exercise
		for i := range exercises {
			if exercises[i].ID == eid {
				ex = &exercises[i]
				break
			}
		}
		if ex == nil {
			apiErr(w, http.StatusNotFound, "exercise not found")
			return
		}

		active := map[string]any{
			"exercise_id":   ex.ID,
			"exercise_name": ex.Name,
		}
		if ex.BodyPart.Valid {
			active["body_part"] = ex.BodyPart.String
		}

		todaySets := []workoutSetJSON{}
		for _, s := range sets {
			if s.ExerciseID == eid {
				todaySets = append(todaySets, toSetJSON(s))
			}
		}
		active["today_sets"] = todaySets

		prefillReps := 10
		var prefillWeight *float64
		if last, _ := db.LastSetForExercise(u.ID, eid); last != nil {
			prefillReps = last.Reps
			prefillWeight = nfPtr(last.WeightLbs)
		}
		active["prefill_reps"] = prefillReps
		active["prefill_weight_lbs"] = prefillWeight

		lastSets := []workoutSetJSON{}
		if lastSession, _ := db.LastSessionForExercise(u.ID, eid, dateStr); len(lastSession) > 0 {
			active["last_session_date"] = lastSession[0].Date
			for _, s := range lastSession {
				lastSets = append(lastSets, toSetJSON(s))
			}
		}
		active["last_session_sets"] = lastSets

		resp["active"] = active
	}

	writeJSON(w, http.StatusOK, resp)
}

// POST /api/workout/set
func APIWorkoutAddSet(w http.ResponseWriter, r *http.Request, u *db.User) {
	var req struct {
		Date       string   `json:"date"`
		ExerciseID int64    `json:"exercise_id"`
		Reps       int      `json:"reps"`
		WeightLbs  *float64 `json:"weight_lbs"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	if req.Date == "" {
		req.Date = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", req.Date); err != nil {
		apiErr(w, http.StatusBadRequest, "invalid date")
		return
	}
	if req.ExerciseID <= 0 {
		apiErr(w, http.StatusBadRequest, "exercise_id required")
		return
	}
	if req.Reps <= 0 || req.Reps > 1000 {
		apiErr(w, http.StatusBadRequest, "reps must be 1-1000")
		return
	}
	var weight sql.NullFloat64
	if req.WeightLbs != nil && *req.WeightLbs > 0 {
		weight = sql.NullFloat64{Float64: *req.WeightLbs, Valid: true}
	}
	id, err := db.AddWorkoutSet(u.ID, req.Date, req.ExerciseID, req.Reps, weight)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "save failed: "+err.Error())
		return
	}
	created, err := db.GetWorkoutSet(u.ID, id)
	if err != nil || created == nil {
		apiErr(w, http.StatusInternalServerError, "saved but could not reload set")
		return
	}
	writeJSON(w, http.StatusCreated, toSetJSON(*created))
}

// PUT /api/workout/set/{id}
func APIWorkoutUpdateSet(w http.ResponseWriter, r *http.Request, u *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	existing, err := db.GetWorkoutSet(u.ID, id)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	if existing == nil {
		apiErr(w, http.StatusNotFound, "set not found")
		return
	}
	var req struct {
		Reps      int      `json:"reps"`
		WeightLbs *float64 `json:"weight_lbs"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	if req.Reps <= 0 || req.Reps > 1000 {
		apiErr(w, http.StatusBadRequest, "reps must be 1-1000")
		return
	}
	var weight sql.NullFloat64
	if req.WeightLbs != nil && *req.WeightLbs > 0 {
		weight = sql.NullFloat64{Float64: *req.WeightLbs, Valid: true}
	}
	ok, err := db.UpdateWorkoutSet(u.ID, id, req.Reps, weight)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "update failed")
		return
	}
	if !ok {
		apiErr(w, http.StatusNotFound, "set not found")
		return
	}
	updated, _ := db.GetWorkoutSet(u.ID, id)
	writeJSON(w, http.StatusOK, toSetJSON(*updated))
}

// DELETE /api/workout/set/{id}
func APIWorkoutDeleteSet(w http.ResponseWriter, r *http.Request, u *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	ok, err := db.DeleteWorkoutSet(u.ID, id)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "delete failed")
		return
	}
	if !ok {
		apiErr(w, http.StatusNotFound, "set not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type prJSON struct {
	MaxWeightLbs *float64 `json:"max_weight_lbs"`
	MaxReps      int      `json:"max_reps"`
}

type exerciseJSON struct {
	ID       int64   `json:"id"`
	Name     string  `json:"name"`
	BodyPart *string `json:"body_part"`
	SetCount int     `json:"set_count"`
	PR       *prJSON `json:"pr"`
}

func toExerciseJSON(e db.Exercise, setCount int, pr *db.ExercisePR) exerciseJSON {
	ej := exerciseJSON{ID: e.ID, Name: e.Name, SetCount: setCount}
	if e.BodyPart.Valid {
		bp := e.BodyPart.String
		ej.BodyPart = &bp
	}
	if pr != nil && pr.MaxReps > 0 {
		p := &prJSON{MaxReps: pr.MaxReps}
		if pr.MaxWeightLbs.Valid {
			w := pr.MaxWeightLbs.Float64
			p.MaxWeightLbs = &w
		}
		ej.PR = p
	}
	return ej
}

// GET /api/exercises
func APIExercises(w http.ResponseWriter, r *http.Request, u *db.User) {
	exercises, err := db.ListExercises()
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	counts, _ := db.CountSetsForExercises(u.ID)
	prs, _ := db.ExercisePRsAll(u.ID)
	out := make([]exerciseJSON, 0, len(exercises))
	for _, e := range exercises {
		var pr *db.ExercisePR
		if p, ok := prs[e.ID]; ok {
			pr = &p
		}
		out = append(out, toExerciseJSON(e, counts[e.ID], pr))
	}
	bps, _ := db.ListBodyParts()
	if bps == nil {
		bps = []string{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"exercises":  out,
		"body_parts": bps,
	})
}

// POST /api/exercises
func APIExerciseCreate(w http.ResponseWriter, r *http.Request, _ *db.User) {
	var req struct {
		Name     string `json:"name"`
		BodyPart string `json:"body_part"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		apiErr(w, http.StatusBadRequest, "name required")
		return
	}
	id, err := db.CreateExercise(req.Name, strings.TrimSpace(req.BodyPart))
	if err != nil {
		apiErr(w, http.StatusConflict, "could not create (name already exists?)")
		return
	}
	e := db.Exercise{ID: id, Name: req.Name}
	if req.BodyPart != "" {
		e.BodyPart = sql.NullString{String: req.BodyPart, Valid: true}
	}
	writeJSON(w, http.StatusCreated, toExerciseJSON(e, 0, nil))
}

// PUT /api/exercises/{id}
func APIExerciseUpdate(w http.ResponseWriter, r *http.Request, u *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	var req struct {
		Name     string `json:"name"`
		BodyPart string `json:"body_part"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		apiErr(w, http.StatusBadRequest, "name required")
		return
	}
	if err := db.UpdateExercise(id, req.Name, strings.TrimSpace(req.BodyPart)); err != nil {
		apiErr(w, http.StatusConflict, "update failed: "+err.Error())
		return
	}
	counts, _ := db.CountSetsForExercises(u.ID)
	e := db.Exercise{ID: id, Name: req.Name}
	if req.BodyPart != "" {
		e.BodyPart = sql.NullString{String: req.BodyPart, Valid: true}
	}
	writeJSON(w, http.StatusOK, toExerciseJSON(e, counts[id], nil))
}

// DELETE /api/exercises/{id}
func APIExerciseDelete(w http.ResponseWriter, r *http.Request, _ *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	if err := db.DeleteExercise(id); err != nil {
		apiErr(w, http.StatusConflict, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /api/body-parts
func APIBodyParts(w http.ResponseWriter, r *http.Request, _ *db.User) {
	bps, err := db.ListBodyParts()
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	counts, _ := db.CountExercisesByBodyPart()
	type bpJSON struct {
		Name          string `json:"name"`
		ExerciseCount int    `json:"exercise_count"`
	}
	out := make([]bpJSON, 0, len(bps))
	for _, name := range bps {
		out = append(out, bpJSON{Name: name, ExerciseCount: counts[name]})
	}
	writeJSON(w, http.StatusOK, map[string]any{"body_parts": out})
}

// POST /api/body-parts
func APIBodyPartCreate(w http.ResponseWriter, r *http.Request, _ *db.User) {
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	name := strings.ToLower(strings.TrimSpace(req.Name))
	if name == "" {
		apiErr(w, http.StatusBadRequest, "name required")
		return
	}
	if err := db.CreateBodyPart(name); err != nil {
		apiErr(w, http.StatusConflict, "could not add (already exists?)")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"name": name, "exercise_count": 0})
}

// DELETE /api/body-parts/{name}
func APIBodyPartDelete(w http.ResponseWriter, r *http.Request, _ *db.User) {
	name := strings.TrimSpace(r.PathValue("name"))
	if name == "" {
		apiErr(w, http.StatusBadRequest, "name required")
		return
	}
	if err := db.DeleteBodyPart(name); err != nil {
		apiErr(w, http.StatusConflict, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
