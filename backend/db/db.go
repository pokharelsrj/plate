package db

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

var DB *sql.DB

// Every table that holds a person's data carries user_id. The exercise library
// and its body-part tags are deliberately shared: they're a catalogue, not
// personal data, and splitting them per user would mean everyone retyping
// "Bench Press".
const schema = `
CREATE TABLE IF NOT EXISTS gym_checkins (
	user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	checkin_id INTEGER NOT NULL,
	club_id    INTEGER NOT NULL,
	checkin_at TIMESTAMP NOT NULL,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (user_id, checkin_id)
);
CREATE INDEX IF NOT EXISTS idx_checkin_at ON gym_checkins(user_id, checkin_at);

CREATE TABLE IF NOT EXISTS nutrition_days (
	user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	date              TEXT NOT NULL,
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
	updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS body_metrics (
	user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	date            TEXT NOT NULL,
	weight_lbs      REAL,
	bf_chest_mm     REAL,
	bf_abdomen_mm   REAL,
	bf_thigh_mm     REAL,
	bf_percent      REAL,
	updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (user_id, date)
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
	user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	date        TEXT NOT NULL,
	exercise_id INTEGER NOT NULL REFERENCES exercises(id),
	reps        INTEGER NOT NULL,
	weight_lbs  REAL,
	created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ws_date ON workout_sets(user_id, date);
CREATE INDEX IF NOT EXISTS idx_ws_exercise ON workout_sets(user_id, exercise_id);

CREATE TABLE IF NOT EXISTS health_days (
	user_id          INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	date             TEXT NOT NULL,
	steps            INTEGER,
	active_calories  REAL,
	resting_hr       REAL,
	sleep_asleep_h   REAL,
	sleep_deep_h     REAL,
	sleep_rem_h      REAL,
	sleep_core_h     REAL,
	sleep_awake_h    REAL,
	updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS sync_runs (
	id              INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id         INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	source          TEXT NOT NULL,
	started_at      TIMESTAMP NOT NULL,
	completed_at    TIMESTAMP,
	status          TEXT NOT NULL,
	records_synced  INTEGER DEFAULT 0,
	error_message   TEXT
);
CREATE INDEX IF NOT EXISTS idx_sync_runs_source_started ON sync_runs(user_id, source, started_at DESC);

CREATE TABLE IF NOT EXISTS users (
	id              INTEGER PRIMARY KEY AUTOINCREMENT,
	email           TEXT UNIQUE NOT NULL COLLATE NOCASE,
	display_name    TEXT,
	password_hash   TEXT NOT NULL,
	api_key         TEXT UNIQUE NOT NULL,
	role            TEXT NOT NULL DEFAULT 'user',
	date_of_birth   TEXT,
	sex             TEXT,
	is_active       INTEGER NOT NULL DEFAULT 1,
	created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_users_api_key ON users(api_key);
`

// schemaVersion is the migration level this binary expects. Bump it and add a
// case to migrate() when the shape changes.
const schemaVersion = 2

func Open(path string) error {
	d, err := sql.Open("sqlite", path+
		"?_pragma=journal_mode(WAL)"+
		"&_pragma=busy_timeout(5000)"+
		"&_pragma=foreign_keys(1)")
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	// SQLite is single-writer; one connection keeps the driver from tripping
	// over itself and makes the migration below atomic by construction.
	d.SetMaxOpenConns(1)
	DB = d

	if err := migrate(); err != nil {
		DB = nil
		d.Close()
		return fmt.Errorf("migrate: %w", err)
	}
	return nil
}

func migrate() error {
	var version int
	if err := DB.QueryRow(`PRAGMA user_version`).Scan(&version); err != nil {
		return fmt.Errorf("read version: %w", err)
	}

	// Databases predating migrations report 0. There's nothing to do for v1
	// itself — it's just the name for "the original single-tenant shape".
	if version < 2 {
		if err := addUserIDColumns(); err != nil {
			return fmt.Errorf("v2 (per-user data): %w", err)
		}
	}

	// Creates anything still missing: every table on a fresh database, nothing
	// at all on one that's already current.
	if _, err := DB.Exec(schema); err != nil {
		return fmt.Errorf("schema: %w", err)
	}

	if version < schemaVersion {
		if _, err := DB.Exec(fmt.Sprintf(`PRAGMA user_version = %d`, schemaVersion)); err != nil {
			return fmt.Errorf("set version: %w", err)
		}
	}
	return nil
}

// addUserIDColumns rebuilds the single-tenant tables with a user_id column and
// hands every existing row to the instance's first admin — on the original
// deployment that's the one person whose data it always was.
//
// SQLite can't add a column to a primary key, so each table is recreated and
// copied. Tables that don't exist yet (a fresh database) are skipped; the
// schema will create them in the new shape directly.
func addUserIDColumns() error {
	legacy := []struct {
		table   string
		columns string // shared by both tables, so the copy can be explicit
	}{
		{"gym_checkins", "checkin_id, club_id, checkin_at, created_at"},
		{"nutrition_days", `date, calories, calorie_budget, protein_g, protein_budget_g,
			carb_g, carb_budget_g, fat_g, fat_budget_g, fibre_g, fibre_budget_g, updated_at`},
		{"body_metrics", `date, weight_lbs, bf_chest_mm, bf_abdomen_mm, bf_thigh_mm,
			bf_percent, updated_at`},
		{"workout_sets", "id, date, exercise_id, reps, weight_lbs, created_at"},
		{"health_days", `date, steps, active_calories, resting_hr, sleep_asleep_h,
			sleep_deep_h, sleep_rem_h, sleep_core_h, sleep_awake_h, updated_at`},
		{"sync_runs", `id, source, started_at, completed_at, status, records_synced,
			error_message`},
	}

	// Nothing to migrate unless at least one legacy table is actually present
	// and still missing the column.
	var pending []int
	for i, t := range legacy {
		exists, err := tableExists(t.table)
		if err != nil {
			return err
		}
		if !exists {
			continue
		}
		has, err := columnExists(t.table, "user_id")
		if err != nil {
			return err
		}
		if !has {
			pending = append(pending, i)
		}
	}
	if len(pending) == 0 {
		return nil
	}

	owner, err := firstAdminID()
	if err != nil {
		return err
	}

	// Foreign keys must be off while tables are swapped, and the pragma is a
	// no-op inside a transaction, so it's toggled around one.
	if _, err := DB.Exec(`PRAGMA foreign_keys = OFF`); err != nil {
		return err
	}
	defer DB.Exec(`PRAGMA foreign_keys = ON`)

	tx, err := DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, i := range pending {
		t := legacy[i]
		if _, err := tx.Exec(fmt.Sprintf(`ALTER TABLE %s RENAME TO %s_old`, t.table, t.table)); err != nil {
			return fmt.Errorf("rename %s: %w", t.table, err)
		}
	}
	// Drop the stale indexes, which followed their tables through the rename
	// and would collide with the ones the schema recreates.
	if err := dropLegacyIndexes(tx); err != nil {
		return err
	}
	if _, err := tx.Exec(schema); err != nil {
		return fmt.Errorf("create new tables: %w", err)
	}
	for _, i := range pending {
		t := legacy[i]
		_, err := tx.Exec(fmt.Sprintf(
			`INSERT INTO %s (user_id, %s) SELECT %d, %s FROM %s_old`,
			t.table, t.columns, owner, t.columns, t.table))
		if err != nil {
			return fmt.Errorf("copy %s: %w", t.table, err)
		}
		if _, err := tx.Exec(fmt.Sprintf(`DROP TABLE %s_old`, t.table)); err != nil {
			return fmt.Errorf("drop %s_old: %w", t.table, err)
		}
	}
	return tx.Commit()
}

// firstAdminID picks the account that inherits pre-migration data: the oldest
// admin, or failing that the oldest account. A database with rows but no users
// predates accounts entirely, so it falls back to 1 — the id SeedAdminFromEnv
// is about to hand the admin it creates.
func firstAdminID() (int64, error) {
	var id int64
	err := DB.QueryRow(`
		SELECT id FROM users
		ORDER BY (role = 'admin') DESC, id ASC
		LIMIT 1
	`).Scan(&id)
	if err == sql.ErrNoRows {
		return 1, nil
	}
	if err != nil {
		// No users table at all on a database old enough to predate accounts.
		if exists, e := tableExists("users"); e == nil && !exists {
			return 1, nil
		}
		return 0, err
	}
	return id, nil
}

func dropLegacyIndexes(tx *sql.Tx) error {
	for _, idx := range []string{
		"idx_checkin_at", "idx_ws_date", "idx_ws_exercise",
		"idx_sync_runs_source_started",
	} {
		if _, err := tx.Exec(`DROP INDEX IF EXISTS ` + idx); err != nil {
			return fmt.Errorf("drop index %s: %w", idx, err)
		}
	}
	return nil
}

func tableExists(name string) (bool, error) {
	var n int
	err := DB.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?`, name).Scan(&n)
	return n > 0, err
}

func columnExists(table, column string) (bool, error) {
	rows, err := DB.Query(fmt.Sprintf(`PRAGMA table_info(%s)`, table))
	if err != nil {
		return false, err
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, ctype string
		var notNull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return false, err
		}
		if name == column {
			return true, rows.Err()
		}
	}
	return false, rows.Err()
}
