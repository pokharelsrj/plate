package db

import (
	"database/sql"
	"time"
)

type SyncRun struct {
	ID            int64
	Source        string
	StartedAt     time.Time
	CompletedAt   sql.NullTime
	Status        string
	RecordsSynced int
	ErrorMessage  sql.NullString
}

func StartSyncRun(userID int64, source string) (int64, error) {
	res, err := DB.Exec(`
		INSERT INTO sync_runs (user_id, source, started_at, status)
		VALUES (?, ?, ?, 'running')
	`, userID, source, time.Now().UTC())
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func FinishSyncRun(id int64, records int, err error) error {
	status := "success"
	var msg sql.NullString
	if err != nil {
		status = "failure"
		msg = sql.NullString{String: err.Error(), Valid: true}
	}
	_, e := DB.Exec(`
		UPDATE sync_runs
		SET completed_at = ?, status = ?, records_synced = ?, error_message = ?
		WHERE id = ?
	`, time.Now().UTC(), status, records, msg, id)
	return e
}

func RecentSyncRuns(userID int64, limit int) ([]SyncRun, error) {
	rows, err := DB.Query(`
		SELECT id, source, started_at, completed_at, status, records_synced, error_message
		FROM sync_runs
		WHERE user_id = ?
		ORDER BY started_at DESC
		LIMIT ?
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []SyncRun
	for rows.Next() {
		var r SyncRun
		if err := rows.Scan(&r.ID, &r.Source, &r.StartedAt, &r.CompletedAt, &r.Status, &r.RecordsSynced, &r.ErrorMessage); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func LastSuccessfulSync(userID int64, source string) (*SyncRun, error) {
	row := DB.QueryRow(`
		SELECT id, source, started_at, completed_at, status, records_synced, error_message
		FROM sync_runs
		WHERE user_id = ? AND source = ? AND status = 'success'
		ORDER BY started_at DESC
		LIMIT 1
	`, userID, source)
	var r SyncRun
	if err := row.Scan(&r.ID, &r.Source, &r.StartedAt, &r.CompletedAt, &r.Status, &r.RecordsSynced, &r.ErrorMessage); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &r, nil
}
