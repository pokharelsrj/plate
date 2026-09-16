package handlers

import "plate/db"

// workoutGroup collects one exercise's sets from a session, in the order the
// exercises were first logged.
type workoutGroup struct {
	ExerciseID   int64
	ExerciseName string
	BodyPart     string
	Sets         []db.WorkoutSet
}

func groupSetsByExercise(sets []db.WorkoutSet) []workoutGroup {
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
	out := make([]workoutGroup, 0, len(order))
	for _, id := range order {
		b := m[id]
		out = append(out, workoutGroup{
			ExerciseID:   id,
			ExerciseName: b.ExerciseName,
			BodyPart:     b.BodyPart,
			Sets:         b.Sets,
		})
	}
	return out
}
