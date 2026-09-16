package db

import (
	"database/sql"
	"time"
)

type BodyMetric struct {
	Date      string
	WeightLbs sql.NullFloat64
	ChestMm   sql.NullFloat64
	AbdomenMm sql.NullFloat64
	ThighMm   sql.NullFloat64
	BfPercent sql.NullFloat64
}

func UpsertBodyMetric(userID int64, b BodyMetric) error {
	_, err := DB.Exec(`
		INSERT INTO body_metrics (user_id, date, weight_lbs, bf_chest_mm, bf_abdomen_mm, bf_thigh_mm, bf_percent, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(user_id, date) DO UPDATE SET
			weight_lbs    = COALESCE(excluded.weight_lbs,    weight_lbs),
			bf_chest_mm   = COALESCE(excluded.bf_chest_mm,   bf_chest_mm),
			bf_abdomen_mm = COALESCE(excluded.bf_abdomen_mm, bf_abdomen_mm),
			bf_thigh_mm   = COALESCE(excluded.bf_thigh_mm,   bf_thigh_mm),
			bf_percent    = COALESCE(excluded.bf_percent,    bf_percent),
			updated_at    = CURRENT_TIMESTAMP
	`, userID, b.Date, b.WeightLbs, b.ChestMm, b.AbdomenMm, b.ThighMm, b.BfPercent)
	return err
}

func BodyBetween(userID int64, from, to time.Time) (map[string]BodyMetric, error) {
	rows, err := DB.Query(`
		SELECT date, weight_lbs, bf_chest_mm, bf_abdomen_mm, bf_thigh_mm, bf_percent
		FROM body_metrics
		WHERE user_id = ? AND date >= ? AND date <= ?
		ORDER BY date ASC
	`, userID, from.Format("2006-01-02"), to.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]BodyMetric{}
	for rows.Next() {
		var b BodyMetric
		if err := rows.Scan(&b.Date, &b.WeightLbs, &b.ChestMm, &b.AbdomenMm, &b.ThighMm, &b.BfPercent); err != nil {
			return nil, err
		}
		out[b.Date] = b
	}
	return out, rows.Err()
}

func RecentBodyMetrics(userID int64, limit int) ([]BodyMetric, error) {
	rows, err := DB.Query(`
		SELECT date, weight_lbs, bf_chest_mm, bf_abdomen_mm, bf_thigh_mm, bf_percent
		FROM body_metrics
		WHERE user_id = ?
		ORDER BY date DESC
		LIMIT ?
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []BodyMetric
	for rows.Next() {
		var b BodyMetric
		if err := rows.Scan(&b.Date, &b.WeightLbs, &b.ChestMm, &b.AbdomenMm, &b.ThighMm, &b.BfPercent); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}
