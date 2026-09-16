package db

import "time"

type GymCheckin struct {
	CheckinID int64
	ClubID    int
	CheckinAt time.Time
}

func UpsertCheckin(c GymCheckin) error {
	_, err := DB.Exec(`
		INSERT INTO gym_checkins (checkin_id, club_id, checkin_at)
		VALUES (?, ?, ?)
		ON CONFLICT(checkin_id) DO NOTHING
	`, c.CheckinID, c.ClubID, c.CheckinAt.UTC())
	return err
}

func CheckinDatesBetween(from, to time.Time) (map[string][]time.Time, error) {
	rows, err := DB.Query(`
		SELECT checkin_at FROM gym_checkins
		WHERE checkin_at >= ? AND checkin_at < ?
		ORDER BY checkin_at ASC
	`, from.UTC(), to.UTC())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string][]time.Time{}
	for rows.Next() {
		var t time.Time
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		local := t.Local()
		key := local.Format("2006-01-02")
		out[key] = append(out[key], local)
	}
	return out, rows.Err()
}

func CheckinCount() (int, error) {
	var n int
	err := DB.QueryRow(`SELECT COUNT(*) FROM gym_checkins`).Scan(&n)
	return n, err
}
