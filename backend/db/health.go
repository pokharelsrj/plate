package db

import (
	"database/sql"
	"time"
)

type HealthDay struct {
	Date           string
	Steps          sql.NullInt64
	ActiveCalories sql.NullFloat64
	RestingHR      sql.NullFloat64
	SleepAsleepH   sql.NullFloat64
	SleepDeepH     sql.NullFloat64
	SleepRemH      sql.NullFloat64
	SleepCoreH     sql.NullFloat64
	SleepAwakeH    sql.NullFloat64
}

func UpsertHealthDay(userID int64, h HealthDay) error {
	_, err := DB.Exec(`
		INSERT INTO health_days
			(user_id, date, steps, active_calories, resting_hr,
			 sleep_asleep_h, sleep_deep_h, sleep_rem_h, sleep_core_h, sleep_awake_h, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(user_id, date) DO UPDATE SET
			steps           = COALESCE(excluded.steps,           steps),
			active_calories = COALESCE(excluded.active_calories, active_calories),
			resting_hr      = COALESCE(excluded.resting_hr,      resting_hr),
			sleep_asleep_h  = COALESCE(excluded.sleep_asleep_h,  sleep_asleep_h),
			sleep_deep_h    = COALESCE(excluded.sleep_deep_h,    sleep_deep_h),
			sleep_rem_h     = COALESCE(excluded.sleep_rem_h,     sleep_rem_h),
			sleep_core_h    = COALESCE(excluded.sleep_core_h,    sleep_core_h),
			sleep_awake_h   = COALESCE(excluded.sleep_awake_h,   sleep_awake_h),
			updated_at      = CURRENT_TIMESTAMP
	`, userID, h.Date, h.Steps, h.ActiveCalories, h.RestingHR,
		h.SleepAsleepH, h.SleepDeepH, h.SleepRemH, h.SleepCoreH, h.SleepAwakeH)
	return err
}

func HealthBetween(userID int64, from, to time.Time) (map[string]HealthDay, error) {
	rows, err := DB.Query(`
		SELECT date, steps, active_calories, resting_hr,
		       sleep_asleep_h, sleep_deep_h, sleep_rem_h, sleep_core_h, sleep_awake_h
		FROM health_days
		WHERE user_id = ? AND date >= ? AND date <= ?
		ORDER BY date ASC
	`, userID, from.Format("2006-01-02"), to.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]HealthDay{}
	for rows.Next() {
		var h HealthDay
		if err := rows.Scan(&h.Date, &h.Steps, &h.ActiveCalories, &h.RestingHR,
			&h.SleepAsleepH, &h.SleepDeepH, &h.SleepRemH, &h.SleepCoreH, &h.SleepAwakeH); err != nil {
			return nil, err
		}
		out[h.Date] = h
	}
	return out, rows.Err()
}
