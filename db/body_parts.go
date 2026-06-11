package db

import "fmt"

// ListBodyParts returns all body part tags, alphabetical.
func ListBodyParts() ([]string, error) {
	rows, err := DB.Query(`SELECT name FROM body_parts ORDER BY name COLLATE NOCASE ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// CreateBodyPart adds a new tag. Returns error if it already exists.
func CreateBodyPart(name string) error {
	_, err := DB.Exec(`INSERT INTO body_parts (name) VALUES (?)`, name)
	return err
}

// DeleteBodyPart removes a tag. Blocks deletion if any exercise references it.
func DeleteBodyPart(name string) error {
	var count int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM exercises WHERE body_part = ? COLLATE NOCASE`, name).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return fmt.Errorf("cannot delete: %d exercise(s) tagged %q", count, name)
	}
	_, err := DB.Exec(`DELETE FROM body_parts WHERE name = ? COLLATE NOCASE`, name)
	return err
}

// CountExercisesByBodyPart returns exercise counts per body part tag.
func CountExercisesByBodyPart() (map[string]int, error) {
	rows, err := DB.Query(`SELECT body_part, COUNT(*) FROM exercises WHERE body_part IS NOT NULL GROUP BY body_part`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var bp string
		var c int
		if err := rows.Scan(&bp, &c); err != nil {
			return nil, err
		}
		out[bp] = c
	}
	return out, rows.Err()
}
