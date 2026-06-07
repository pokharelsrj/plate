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
