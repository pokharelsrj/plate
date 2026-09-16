package db

// AllWorkoutSets returns every logged set with exercise info joined, ordered by
// date then insertion order. Used by the workout-stats analytics, which derives
// all-time PRs plus range-scoped frequency / set-volume / progression in Go.
func AllWorkoutSets() ([]WorkoutSet, error) {
	rows, err := DB.Query(`
		SELECT ws.id, ws.date, ws.exercise_id, ws.reps, ws.weight_lbs, ws.created_at,
		       e.name, e.body_part
		FROM workout_sets ws
		JOIN exercises e ON e.id = ws.exercise_id
		ORDER BY ws.date ASC, ws.created_at ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WorkoutSet
	for rows.Next() {
		var s WorkoutSet
		if err := rows.Scan(&s.ID, &s.Date, &s.ExerciseID, &s.Reps, &s.WeightLbs, &s.CreatedAt,
			&s.ExerciseName, &s.BodyPart); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
