// Command seed-demo fills one account with plausible history.
//
// It exists for App Review: a reviewer signing into a brand-new account sees
// empty screens, which reads as a broken app. It's also handy for poking at
// the charts without waiting months to accumulate real data.
//
// The account is wiped and regenerated on every run, and the generator is
// deterministic, so re-running produces the same history. Only that user's
// rows are touched — nobody else's data, and not the shared exercise library,
// which it reads but never writes.
//
//	go run ./cmd/seed-demo -db data.db -email demo@example.com -password secret
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"log"
	"math"
	"math/rand"
	"time"

	"plate/db"
)

func main() {
	dbPath := flag.String("db", "data.db", "path to the SQLite database")
	email := flag.String("email", "", "account to seed (created if it doesn't exist)")
	password := flag.String("password", "", "password, required when creating the account")
	days := flag.Int("days", 120, "how many days of history to generate")
	flag.Parse()

	if *email == "" {
		log.Fatal("-email is required")
	}
	if err := db.Open(*dbPath); err != nil {
		log.Fatalf("open db: %v", err)
	}

	u, err := db.UserByEmail(*email)
	if err != nil {
		log.Fatalf("lookup: %v", err)
	}
	if u == nil {
		if *password == "" {
			log.Fatalf("%s doesn't exist yet — pass -password to create it", *email)
		}
		u, err = db.CreateUser(*email, *password, "Demo", "user", "1995-04-12", "male")
		if err != nil {
			log.Fatalf("create user: %v", err)
		}
		fmt.Printf("created account %s (id %d)\n", u.Email, u.ID)
	} else {
		fmt.Printf("reusing account %s (id %d)\n", u.Email, u.ID)
	}

	if err := wipe(u.ID); err != nil {
		log.Fatalf("wipe: %v", err)
	}
	lib, err := library()
	if err != nil {
		log.Fatalf("read exercise library: %v", err)
	}
	if len(lib) == 0 {
		log.Fatal("the shared exercise library is empty — nothing to log sets against")
	}

	s := &seeder{user: u.ID, rng: rand.New(rand.NewSource(20260916)), lib: lib}
	if err := s.run(*days); err != nil {
		log.Fatalf("seed: %v", err)
	}

	fmt.Printf("\nseeded %d days for %s\n", *days, u.Email)
	fmt.Printf("  workout sets   %d across %d sessions\n", s.sets, s.sessions)
	fmt.Printf("  weigh-ins      %d (%d with calipers)\n", s.weighIns, s.calipers)
	fmt.Printf("  health days    %d\n", s.healthDays)
	fmt.Printf("  nutrition days %d\n", s.nutriDays)
	fmt.Printf("  gym check-ins  %d\n", s.checkins)
	fmt.Printf("\napi key: %s\n", u.APIKey)
}

// wipe clears this user's rows so a re-run replaces rather than duplicates.
func wipe(userID int64) error {
	for _, t := range []string{
		"workout_sets", "body_metrics", "health_days", "nutrition_days",
		"gym_checkins", "sync_runs",
	} {
		if _, err := db.DB.Exec(fmt.Sprintf(`DELETE FROM %s WHERE user_id = ?`, t), userID); err != nil {
			return fmt.Errorf("%s: %w", t, err)
		}
	}
	return nil
}

// library groups the shared exercises by body part.
func library() (map[string][]db.Exercise, error) {
	all, err := db.ListExercises()
	if err != nil {
		return nil, err
	}
	out := map[string][]db.Exercise{}
	for _, e := range all {
		if e.BodyPart.Valid {
			out[e.BodyPart.String] = append(out[e.BodyPart.String], e)
		}
	}
	return out, nil
}

type seeder struct {
	user int64
	rng  *rand.Rand
	lib  map[string][]db.Exercise

	sessions, sets, weighIns, calipers, healthDays, nutriDays, checkins int
}

// A rotating split. Rest days are the gaps.
var split = map[time.Weekday][]string{
	time.Monday:    {"chest", "shoulders", "arms"},
	time.Tuesday:   {"back", "arms"},
	time.Thursday:  {"legs", "traps"},
	time.Saturday:  {"chest", "back"},
	time.Wednesday: nil,
	time.Friday:    nil,
	time.Sunday:    nil,
}

func (s *seeder) run(days int) error {
	today := time.Now()
	start := today.AddDate(0, 0, -days+1)
	weight := 183.0

	for d := start; !d.After(today); d = d.AddDate(0, 0, 1) {
		day := d.Format("2006-01-02")
		progress := float64(d.Sub(start)) / float64(today.Sub(start)+1)

		trained := false
		// Always train on the last day so the app opens on a populated
		// Today/Workout screen rather than a rest day's empty state.
		isLast := d.Format("2006-01-02") == today.Format("2006-01-02")
		parts := split[d.Weekday()]
		if isLast && len(parts) == 0 {
			parts = []string{"chest", "arms"}
		}
		if len(parts) > 0 && (isLast || s.rng.Float64() > 0.12) {
			if err := s.session(day, parts, progress); err != nil {
				return err
			}
			if err := s.checkin(d); err != nil {
				return err
			}
			trained = true
		}

		// A slow cut with day-to-day water noise, which is the whole reason
		// the app shows weekly averages.
		weight = 183.0 - 7.0*progress + s.rng.NormFloat64()*0.7
		if s.rng.Float64() < 0.85 {
			b := db.BodyMetric{Date: day, WeightLbs: f(round1(weight))}
			// Calipers roughly every other Sunday.
			if d.Weekday() == time.Sunday && s.rng.Float64() < 0.5 {
				chest := 9.5 - 2.0*progress + s.rng.NormFloat64()*0.4
				abd := 21.0 - 5.0*progress + s.rng.NormFloat64()*0.6
				thigh := 14.0 - 3.0*progress + s.rng.NormFloat64()*0.5
				b.ChestMm, b.AbdomenMm, b.ThighMm = f(round1(chest)), f(round1(abd)), f(round1(thigh))
				b.BfPercent = f(round1(jacksonPollock3Site(31, chest, abd, thigh)))
				s.calipers++
			}
			if err := db.UpsertBodyMetric(s.user, b); err != nil {
				return err
			}
			s.weighIns++
		}

		if s.rng.Float64() < 0.93 {
			if err := s.health(day, trained); err != nil {
				return err
			}
		}
		if s.rng.Float64() < 0.88 {
			if err := s.nutrition(day, trained); err != nil {
				return err
			}
		}
	}
	return nil
}

// Rough top-set loads by body part, so isolation work doesn't come out at
// barbell weights. Lower and upper bounds in lb.
var loadRange = map[string][2]float64{
	"chest":     {95, 205},
	"back":      {80, 190},
	"legs":      {135, 285},
	"shoulders": {25, 75},
	"arms":      {20, 70},
	"traps":     {70, 160},
}

func (s *seeder) session(day string, parts []string, progress float64) error {
	s.sessions++
	for _, part := range parts {
		pool := s.lib[part]
		if len(pool) == 0 {
			continue
		}
		n := 2
		if len(pool) > 3 && s.rng.Float64() < 0.6 {
			n = 3
		}
		for i := 0; i < n && i < len(pool); i++ {
			ex := pool[s.rng.Intn(len(pool))]
			// Spread exercises across the body part's plausible range by id,
			// then nudge everything upward across the block.
			lo, hi := 45.0, 135.0
			if r, ok := loadRange[part]; ok {
				lo, hi = r[0], r[1]
			}
			base := lo + (hi-lo)*float64(ex.ID%7)/6.0
			base *= 1 + 0.18*progress
			for set := 0; set < 3+s.rng.Intn(2); set++ {
				reps := 6 + s.rng.Intn(7)
				w := math.Round((base-float64(set)*2.5+s.rng.NormFloat64()*3)/2.5) * 2.5
				var weight sql.NullFloat64
				if w > 0 {
					weight = f(w)
				}
				if _, err := db.AddWorkoutSet(s.user, day, ex.ID, reps, weight); err != nil {
					return err
				}
				s.sets++
			}
		}
	}
	return nil
}

func (s *seeder) checkin(d time.Time) error {
	at := time.Date(d.Year(), d.Month(), d.Day(), 17+s.rng.Intn(3), s.rng.Intn(60), 0, 0, time.Local)
	id := at.Unix()
	if err := db.UpsertCheckin(s.user, db.GymCheckin{CheckinID: id, ClubID: 1234, CheckinAt: at}); err != nil {
		return err
	}
	s.checkins++
	return nil
}

func (s *seeder) health(day string, trained bool) error {
	steps := int64(5200 + s.rng.Intn(4200))
	if trained {
		steps += int64(2600 + s.rng.Intn(3200))
	}
	deep := 0.8 + s.rng.Float64()*0.8
	rem := 1.2 + s.rng.Float64()*0.9
	core := 3.4 + s.rng.Float64()*1.4
	awake := 0.2 + s.rng.Float64()*0.4
	h := db.HealthDay{
		Date:           day,
		Steps:          sql.NullInt64{Int64: steps, Valid: true},
		ActiveCalories: f(round1(320 + s.rng.Float64()*380)),
		RestingHR:      f(round1(53 + s.rng.Float64()*8)),
		SleepAsleepH:   f(round1(deep + rem + core)),
		SleepDeepH:     f(round1(deep)),
		SleepRemH:      f(round1(rem)),
		SleepCoreH:     f(round1(core)),
		SleepAwakeH:    f(round1(awake)),
	}
	if err := db.UpsertHealthDay(s.user, h); err != nil {
		return err
	}
	s.healthDays++
	return nil
}

func (s *seeder) nutrition(day string, trained bool) error {
	cal := 1950.0 + s.rng.Float64()*520
	if trained {
		cal += 180
	}
	protein := 145 + s.rng.Float64()*45
	fat := 55 + s.rng.Float64()*25
	carb := (cal - protein*4 - fat*9) / 4
	n := db.NutritionDay{
		Date:           day,
		Calories:       f(round1(cal)),
		CalorieBudget:  f(2300),
		ProteinG:       f(round1(protein)),
		ProteinBudgetG: f(170),
		CarbG:          f(round1(carb)),
		CarbBudgetG:    f(230),
		FatG:           f(round1(fat)),
		FatBudgetG:     f(70),
		FibreG:         f(round1(22 + s.rng.Float64()*14)),
		FibreBudgetG:   f(30),
	}
	if err := db.UpsertNutrition(s.user, n); err != nil {
		return err
	}
	s.nutriDays++
	return nil
}

// jacksonPollock3Site mirrors the server's body-fat formula so the seeded
// bf_percent agrees with what the app would compute from the same skinfolds.
func jacksonPollock3Site(age int, chest, abdomen, thigh float64) float64 {
	sum := chest + abdomen + thigh
	d := 1.10938 - 0.0008267*sum + 0.0000016*sum*sum - 0.0002574*float64(age)
	if d <= 0 {
		return 0
	}
	return 495.0/d - 450.0
}

func round1(v float64) float64    { return math.Round(v*10) / 10 }
func f(v float64) sql.NullFloat64 { return sql.NullFloat64{Float64: v, Valid: true} }
