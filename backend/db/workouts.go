package db

import (
	"database/sql"
	"fmt"
	"time"
)

type Exercise struct {
	ID       int64
	Name     string
	BodyPart sql.NullString
}

type WorkoutSet struct {
	ID         int64
	Date       string
	ExerciseID int64
	Reps       int
	WeightLbs  sql.NullFloat64
	CreatedAt  time.Time
	// joined fields
	ExerciseName string
	BodyPart     sql.NullString
}

// ListExercises returns all exercises ordered by name.
func ListExercises() ([]Exercise, error) {
	rows, err := DB.Query(`SELECT id, name, body_part FROM exercises ORDER BY name COLLATE NOCASE ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Exercise
	for rows.Next() {
		var e Exercise
		if err := rows.Scan(&e.ID, &e.Name, &e.BodyPart); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// CreateExercise inserts a new exercise. Returns ErrConstraintUnique-style error if name already exists.
func CreateExercise(name, bodyPart string) (int64, error) {
	var bp sql.NullString
	if bodyPart != "" {
		bp = sql.NullString{String: bodyPart, Valid: true}
	}
	res, err := DB.Exec(`INSERT INTO exercises (name, body_part) VALUES (?, ?)`, name, bp)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// AddWorkoutSet inserts a new set and returns its id.
func AddWorkoutSet(date string, exerciseID int64, reps int, weightLbs sql.NullFloat64) (int64, error) {
	res, err := DB.Exec(`
		INSERT INTO workout_sets (date, exercise_id, reps, weight_lbs)
		VALUES (?, ?, ?, ?)
	`, date, exerciseID, reps, weightLbs)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

// GetWorkoutSet returns one set by id with exercise info joined, or nil if missing.
func GetWorkoutSet(id int64) (*WorkoutSet, error) {
	row := DB.QueryRow(`
		SELECT ws.id, ws.date, ws.exercise_id, ws.reps, ws.weight_lbs, ws.created_at,
		       e.name, e.body_part
		FROM workout_sets ws
		JOIN exercises e ON e.id = ws.exercise_id
		WHERE ws.id = ?
	`, id)
	var s WorkoutSet
	err := row.Scan(&s.ID, &s.Date, &s.ExerciseID, &s.Reps, &s.WeightLbs, &s.CreatedAt,
		&s.ExerciseName, &s.BodyPart)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// DeleteWorkoutSet removes a set by id.
func DeleteWorkoutSet(id int64) error {
	_, err := DB.Exec(`DELETE FROM workout_sets WHERE id = ?`, id)
	return err
}

// UpdateWorkoutSet edits the reps/weight of an existing set.
func UpdateWorkoutSet(id int64, reps int, weightLbs sql.NullFloat64) error {
	_, err := DB.Exec(`UPDATE workout_sets SET reps = ?, weight_lbs = ? WHERE id = ?`, reps, weightLbs, id)
	return err
}

// UpdateExercise renames or re-tags an exercise.
func UpdateExercise(id int64, name, bodyPart string) error {
	var bp sql.NullString
	if bodyPart != "" {
		bp = sql.NullString{String: bodyPart, Valid: true}
	}
	_, err := DB.Exec(`UPDATE exercises SET name = ?, body_part = ? WHERE id = ?`, name, bp, id)
	return err
}

// DeleteExercise removes an exercise. Returns error if there are sets referencing it.
func DeleteExercise(id int64) error {
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM workout_sets WHERE exercise_id = ?`, id).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("cannot delete: exercise has %d logged sets", count)
	}
	_, err := DB.Exec(`DELETE FROM exercises WHERE id = ?`, id)
	return err
}

// CountSetsForExercises returns map of exercise_id → number of sets ever logged.
func CountSetsForExercises() (map[int64]int, error) {
	rows, err := DB.Query(`SELECT exercise_id, COUNT(*) FROM workout_sets GROUP BY exercise_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]int{}
	for rows.Next() {
		var id int64
		var c int
		if err := rows.Scan(&id, &c); err != nil {
			return nil, err
		}
		out[id] = c
	}
	return out, rows.Err()
}

// WorkoutSetsForDay returns all sets for a given date with exercise info joined, ordered chronologically.
func WorkoutSetsForDay(date string) ([]WorkoutSet, error) {
	rows, err := DB.Query(`
		SELECT ws.id, ws.date, ws.exercise_id, ws.reps, ws.weight_lbs, ws.created_at,
		       e.name, e.body_part
		FROM workout_sets ws
		JOIN exercises e ON e.id = ws.exercise_id
		WHERE ws.date = ?
		ORDER BY ws.created_at ASC
	`, date)
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

// WorkoutSetsBetween returns all sets in a date range, with exercise info.
func WorkoutSetsBetween(from, to time.Time) ([]WorkoutSet, error) {
	rows, err := DB.Query(`
		SELECT ws.id, ws.date, ws.exercise_id, ws.reps, ws.weight_lbs, ws.created_at,
		       e.name, e.body_part
		FROM workout_sets ws
		JOIN exercises e ON e.id = ws.exercise_id
		WHERE ws.date >= ? AND ws.date <= ?
		ORDER BY ws.date ASC, ws.created_at ASC
	`, from.Format("2006-01-02"), to.Format("2006-01-02"))
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

// LastSetForExercise returns the most recent set across all time for an exercise (or nil if none).
func LastSetForExercise(exerciseID int64) (*WorkoutSet, error) {
	row := DB.QueryRow(`
		SELECT id, date, exercise_id, reps, weight_lbs, created_at
		FROM workout_sets
		WHERE exercise_id = ?
		ORDER BY date DESC, created_at DESC
		LIMIT 1
	`, exerciseID)
	var s WorkoutSet
	err := row.Scan(&s.ID, &s.Date, &s.ExerciseID, &s.Reps, &s.WeightLbs, &s.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// LastSessionForExercise returns sets from the most recent date (before excludeDate) the exercise was performed.
func LastSessionForExercise(exerciseID int64, excludeDate string) ([]WorkoutSet, error) {
	var lastDate string
	err := DB.QueryRow(`
		SELECT MAX(date) FROM workout_sets WHERE exercise_id = ? AND date < ?
	`, exerciseID, excludeDate).Scan(&lastDate)
	if err == sql.ErrNoRows || lastDate == "" {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rows, err := DB.Query(`
		SELECT id, date, exercise_id, reps, weight_lbs, created_at
		FROM workout_sets
		WHERE exercise_id = ? AND date = ?
		ORDER BY created_at ASC
	`, exerciseID, lastDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WorkoutSet
	for rows.Next() {
		var s WorkoutSet
		if err := rows.Scan(&s.ID, &s.Date, &s.ExerciseID, &s.Reps, &s.WeightLbs, &s.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// ExercisePR holds the all-time personal record for one exercise.
type ExercisePR struct {
	ExerciseID   int64
	MaxWeightLbs sql.NullFloat64
	MaxReps      int
}

// ExercisePRsAll returns the all-time PR (max weight + max reps) for every exercise that has sets.
func ExercisePRsAll() (map[int64]ExercisePR, error) {
	rows, err := DB.Query(`
		SELECT exercise_id, MAX(weight_lbs), MAX(reps)
		FROM workout_sets
		GROUP BY exercise_id
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]ExercisePR{}
	for rows.Next() {
		var pr ExercisePR
		if err := rows.Scan(&pr.ExerciseID, &pr.MaxWeightLbs, &pr.MaxReps); err != nil {
			return nil, err
		}
		out[pr.ExerciseID] = pr
	}
	return out, rows.Err()
}

// WorkoutDaysSet returns the set of dates (YYYY-MM-DD) that have at least one set, within the range.
func WorkoutDaysSet(from, to time.Time) (map[string]bool, error) {
	rows, err := DB.Query(`
		SELECT DISTINCT date FROM workout_sets
		WHERE date >= ? AND date <= ?
	`, from.Format("2006-01-02"), to.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var d string
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		out[d] = true
	}
	return out, rows.Err()
}
