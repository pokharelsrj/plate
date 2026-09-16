package handlers

import (
	"math"
	"net/http"
	"sort"
	"time"

	"plate/db"
)

// APIWorkoutStats serves the lifting analytics — PRs, estimated 1RM,
// progressions, and weekly set volume by body part.
func APIWorkoutStats(w http.ResponseWriter, r *http.Request, u *db.User) {
	writeJSON(w, http.StatusOK, buildWorkoutStatsPayload(u.ID, parseRange(r)))
}

func bodyPartOf(s db.WorkoutSet) string {
	if s.BodyPart.Valid && s.BodyPart.String != "" {
		return s.BodyPart.String
	}
	return "other"
}

func hasWeight(s db.WorkoutSet) bool {
	return s.WeightLbs.Valid && s.WeightLbs.Float64 > 0
}

// epley1RM estimates a one-rep max from a working set (Epley formula).
func epley1RM(weightLbs float64, reps int) float64 {
	return weightLbs * (1.0 + float64(reps)/30.0)
}

// daysBetween returns the whole-day difference b-a between two YYYY-MM-DD dates
// (ignoring time of day). Negative if b is before a.
func daysBetween(a, b string) int {
	ta, err1 := time.ParseInLocation("2006-01-02", a, time.Local)
	tb, err2 := time.ParseInLocation("2006-01-02", b, time.Local)
	if err1 != nil || err2 != nil {
		return 0
	}
	return int(tb.Sub(ta).Hours() / 24)
}

// mondayOf returns the Monday (YYYY-MM-DD) of the ISO week containing date string d.
func mondayOf(d string) string {
	t, err := time.ParseInLocation("2006-01-02", d, time.Local)
	if err != nil {
		return d
	}
	offset := (int(t.Weekday()) + 6) % 7 // Mon=0 ... Sun=6
	return t.AddDate(0, 0, -offset).Format("2006-01-02")
}

type prItem struct {
	ExerciseID     int64    `json:"exercise_id"`
	Exercise       string   `json:"exercise"`
	BodyPart       string   `json:"body_part"`
	Sets           int      `json:"sets"`
	IsBodyweight   bool     `json:"is_bodyweight"`
	BestWeightLbs  *float64 `json:"best_weight_lbs"`
	BestWeightReps int      `json:"best_weight_reps"`
	Est1RM         *float64 `json:"est_one_rm"`
	BestReps       int      `json:"best_reps"`
	LastDate       string   `json:"last_date"`
}

type progPoint struct {
	Date      string   `json:"date"`
	Est1RM    *float64 `json:"est_one_rm"`
	TopWeight *float64 `json:"top_weight"`
	BestReps  int      `json:"best_reps"`
}

type progression struct {
	ExerciseID   int64       `json:"exercise_id"`
	Exercise     string      `json:"exercise"`
	BodyPart     string      `json:"body_part"`
	IsBodyweight bool        `json:"is_bodyweight"`
	Points       []progPoint `json:"points"`
}

type weeklySets struct {
	Week       string         `json:"week"`
	Label      string         `json:"label"`
	ByBodyPart map[string]int `json:"by_body_part"`
	Total      int            `json:"total"`
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

func buildWorkoutStatsPayload(userID int64, days int) map[string]any {
	allSets, _ := db.AllWorkoutSets(userID)

	to := time.Now()
	from := to.AddDate(0, 0, -days+1)
	fromStr := from.Format("2006-01-02")
	toStr := to.Format("2006-01-02")
	inRange := func(d string) bool { return d >= fromStr && d <= toStr }

	// ---- All-time PRs, per exercise ----
	type prAccum struct {
		name, bodyPart string
		sets           int
		maxWeight      float64
		maxWeightReps  int
		best1RM        float64
		bestReps       int
		hasWeight      bool
		lastDate       string
	}
	prByEx := map[int64]*prAccum{}
	for _, s := range allSets {
		a := prByEx[s.ExerciseID]
		if a == nil {
			a = &prAccum{name: s.ExerciseName, bodyPart: bodyPartOf(s)}
			prByEx[s.ExerciseID] = a
		}
		a.sets++
		if s.Reps > a.bestReps {
			a.bestReps = s.Reps
		}
		if s.Date > a.lastDate {
			a.lastDate = s.Date
		}
		if hasWeight(s) {
			a.hasWeight = true
			wt := s.WeightLbs.Float64
			// Heaviest set; break ties by more reps.
			if wt > a.maxWeight || (wt == a.maxWeight && s.Reps > a.maxWeightReps) {
				a.maxWeight = wt
				a.maxWeightReps = s.Reps
			}
			if e := epley1RM(wt, s.Reps); e > a.best1RM {
				a.best1RM = e
			}
		}
	}
	prs := make([]prItem, 0, len(prByEx))
	for id, a := range prByEx {
		it := prItem{
			ExerciseID:   id,
			Exercise:     a.name,
			BodyPart:     a.bodyPart,
			Sets:         a.sets,
			IsBodyweight: !a.hasWeight,
			BestReps:     a.bestReps,
			LastDate:     a.lastDate,
		}
		if a.hasWeight {
			bw := a.maxWeight
			e := round1(a.best1RM)
			it.BestWeightLbs = &bw
			it.BestWeightReps = a.maxWeightReps
			it.Est1RM = &e
		}
		prs = append(prs, it)
	}
	// Strongest lifts first (by est 1RM); bodyweight lifts (no 1RM) sink, ordered by reps.
	sort.Slice(prs, func(i, j int) bool {
		ei, ej := prs[i].Est1RM, prs[j].Est1RM
		switch {
		case ei != nil && ej != nil:
			if *ei != *ej {
				return *ei > *ej
			}
		case ei != nil:
			return true
		case ej != nil:
			return false
		default:
			if prs[i].BestReps != prs[j].BestReps {
				return prs[i].BestReps > prs[j].BestReps
			}
		}
		return prs[i].Exercise < prs[j].Exercise
	})

	// ---- Range-scoped aggregates ----
	rangeSets := make([]db.WorkoutSet, 0, len(allSets))
	for _, s := range allSets {
		if inRange(s.Date) {
			rangeSets = append(rangeSets, s)
		}
	}

	// Weekly sets by body part.
	weekIdx := map[string]*weeklySets{}
	var weekOrder []string
	for _, s := range rangeSets {
		wk := mondayOf(s.Date)
		ws := weekIdx[wk]
		if ws == nil {
			ws = &weeklySets{Week: wk, Label: shortDayLabel(wk), ByBodyPart: map[string]int{}}
			weekIdx[wk] = ws
			weekOrder = append(weekOrder, wk)
		}
		ws.ByBodyPart[bodyPartOf(s)]++
		ws.Total++
	}
	sort.Strings(weekOrder)
	weekly := make([]weeklySets, 0, len(weekOrder))
	for _, wk := range weekOrder {
		weekly = append(weekly, *weekIdx[wk])
	}

	// Overall set distribution by body part (range).
	setsByBodyPart := map[string]int{}
	rangeDates := map[string]bool{}
	setCountByEx := map[int64]int{}
	for _, s := range rangeSets {
		setsByBodyPart[bodyPartOf(s)]++
		rangeDates[s.Date] = true
		setCountByEx[s.ExerciseID]++
	}

	// ---- Per-exercise progression (top lifts in range by set count) ----
	type exRef struct {
		id   int64
		sets int
	}
	var refs []exRef
	for id, n := range setCountByEx {
		refs = append(refs, exRef{id, n})
	}
	sort.Slice(refs, func(i, j int) bool {
		if refs[i].sets != refs[j].sets {
			return refs[i].sets > refs[j].sets
		}
		return refs[i].id < refs[j].id
	})
	const maxProgressions = 6
	if len(refs) > maxProgressions {
		refs = refs[:maxProgressions]
	}
	progressions := make([]progression, 0, len(refs))
	for _, ref := range refs {
		// Per-date best 1RM / top weight / best reps for this exercise within range.
		type dayBest struct {
			est1RM, topWeight float64
			hasWeight         bool
			bestReps          int
		}
		byDate := map[string]*dayBest{}
		var dateOrder []string
		var pname, pbp string
		anyWeight := false
		for _, s := range rangeSets {
			if s.ExerciseID != ref.id {
				continue
			}
			pname, pbp = s.ExerciseName, bodyPartOf(s)
			acc := byDate[s.Date]
			if acc == nil {
				acc = &dayBest{}
				byDate[s.Date] = acc
				dateOrder = append(dateOrder, s.Date)
			}
			if s.Reps > acc.bestReps {
				acc.bestReps = s.Reps
			}
			if hasWeight(s) {
				anyWeight = true
				acc.hasWeight = true
				wt := s.WeightLbs.Float64
				if wt > acc.topWeight {
					acc.topWeight = wt
				}
				if e := epley1RM(wt, s.Reps); e > acc.est1RM {
					acc.est1RM = e
				}
			}
		}
		sort.Strings(dateOrder)
		pts := make([]progPoint, 0, len(dateOrder))
		for _, d := range dateOrder {
			b := byDate[d]
			p := progPoint{Date: d, BestReps: b.bestReps}
			if b.hasWeight {
				e := round1(b.est1RM)
				tw := b.topWeight
				p.Est1RM = &e
				p.TopWeight = &tw
			}
			pts = append(pts, p)
		}
		progressions = append(progressions, progression{
			ExerciseID:   ref.id,
			Exercise:     pname,
			BodyPart:     pbp,
			IsBodyweight: !anyWeight,
			Points:       pts,
		})
	}

	// ---- Frequency & consistency ----
	totalSessions := len(rangeDates)
	totalSets := len(rangeSets)
	avgSetsPerSession := 0.0
	if totalSessions > 0 {
		avgSetsPerSession = float64(totalSets) / float64(totalSessions)
	}

	// sessions/week is measured over the active span (first session in range → today),
	// not the whole window — otherwise a couple weeks of logs inside a 90-day range read
	// as a misleadingly tiny rate. Floored at one week so a 2-day burst can't inflate it.
	sessionsPerWeek := 0.0
	if totalSessions > 0 {
		firstInRange := ""
		for d := range rangeDates {
			if firstInRange == "" || d < firstInRange {
				firstInRange = d
			}
		}
		spanDays := daysBetween(firstInRange, toStr) + 1
		weeks := float64(spanDays) / 7.0
		if weeks < 1 {
			weeks = 1
		}
		sessionsPerWeek = float64(totalSessions) / weeks
	}

	// days since last + consecutive-week streak (all-time).
	mondaySet := map[string]bool{}
	lastDate := ""
	for _, s := range allSets {
		mondaySet[mondayOf(s.Date)] = true
		if s.Date > lastDate {
			lastDate = s.Date
		}
	}
	daysSinceLast := -1
	if lastDate != "" {
		daysSinceLast = daysBetween(lastDate, toStr)
		if daysSinceLast < 0 {
			daysSinceLast = 0
		}
	}
	weekStreak := 0
	if lastDate != "" {
		cur := mondayOf(lastDate)
		for mondaySet[cur] {
			weekStreak++
			t, _ := time.ParseInLocation("2006-01-02", cur, time.Local)
			cur = t.AddDate(0, 0, -7).Format("2006-01-02")
		}
	}

	return map[string]any{
		"range_days": days,
		"frequency": map[string]any{
			"total_sessions":       totalSessions,
			"total_sets":           totalSets,
			"avg_sets_per_session": round1(avgSetsPerSession),
			"sessions_per_week":    round1(sessionsPerWeek),
			"days_since_last":      daysSinceLast,
			"week_streak":          weekStreak,
		},
		"prs":               prs,
		"weekly_sets":       weekly,
		"sets_by_body_part": setsByBodyPart,
		"progressions":      progressions,
	}
}

// shortDayLabel turns "2026-06-09" into "Jun 9".
func shortDayLabel(d string) string {
	t, err := time.ParseInLocation("2006-01-02", d, time.Local)
	if err != nil {
		return d
	}
	return t.Format("Jan 2")
}
