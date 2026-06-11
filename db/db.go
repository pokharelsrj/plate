package db

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

var DB *sql.DB

const schema = `
CREATE TABLE IF NOT EXISTS gym_checkins (
	checkin_id INTEGER PRIMARY KEY,
	club_id    INTEGER NOT NULL,
	checkin_at TIMESTAMP NOT NULL,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_checkin_at ON gym_checkins(checkin_at);

CREATE TABLE IF NOT EXISTS nutrition_days (
	date              TEXT PRIMARY KEY,
	calories          REAL,
	calorie_budget    REAL,
	protein_g         REAL,
	protein_budget_g  REAL,
	carb_g            REAL,
	carb_budget_g     REAL,
	fat_g             REAL,
	fat_budget_g      REAL,
	fibre_g           REAL,
	fibre_budget_g    REAL,
	updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS body_metrics (
	date            TEXT PRIMARY KEY,
	weight_lbs      REAL,
	bf_chest_mm     REAL,
	bf_abdomen_mm   REAL,
	bf_thigh_mm     REAL,
	bf_percent      REAL,
	updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS body_parts (
	name       TEXT PRIMARY KEY COLLATE NOCASE,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT OR IGNORE INTO body_parts (name) VALUES
	('chest'), ('back'), ('legs'), ('shoulders'),
	('arms'), ('core'), ('cardio'), ('other');

CREATE TABLE IF NOT EXISTS exercises (
	id          INTEGER PRIMARY KEY AUTOINCREMENT,
	name        TEXT UNIQUE NOT NULL COLLATE NOCASE,
	body_part   TEXT,
	created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS workout_sets (
	id          INTEGER PRIMARY KEY AUTOINCREMENT,
	date        TEXT NOT NULL,
	exercise_id INTEGER NOT NULL REFERENCES exercises(id),
	reps        INTEGER NOT NULL,
	weight_lbs  REAL,
	created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ws_date ON workout_sets(date);
CREATE INDEX IF NOT EXISTS idx_ws_exercise ON workout_sets(exercise_id);

CREATE TABLE IF NOT EXISTS health_days (
	date             TEXT PRIMARY KEY,
	steps            INTEGER,
	active_calories  REAL,
	resting_hr       REAL,
	sleep_asleep_h   REAL,
	sleep_deep_h     REAL,
	sleep_rem_h      REAL,
	sleep_core_h     REAL,
	sleep_awake_h    REAL,
	updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_runs (
	id              INTEGER PRIMARY KEY AUTOINCREMENT,
	source          TEXT NOT NULL,
	started_at      TIMESTAMP NOT NULL,
	completed_at    TIMESTAMP,
	status          TEXT NOT NULL,
	records_synced  INTEGER DEFAULT 0,
	error_message   TEXT
);
CREATE INDEX IF NOT EXISTS idx_sync_runs_source_started ON sync_runs(source, started_at DESC);
`

func Open(path string) error {
	d, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	if _, err := d.Exec(schema); err != nil {
		return fmt.Errorf("schema: %w", err)
	}
	d.SetMaxOpenConns(1)
	DB = d
	return nil
}
