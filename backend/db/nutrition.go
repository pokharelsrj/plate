package db

import (
	"database/sql"
	"time"
)

type NutritionDay struct {
	Date           string
	Calories       sql.NullFloat64
	CalorieBudget  sql.NullFloat64
	ProteinG       sql.NullFloat64
	ProteinBudgetG sql.NullFloat64
	CarbG          sql.NullFloat64
	CarbBudgetG    sql.NullFloat64
	FatG           sql.NullFloat64
	FatBudgetG     sql.NullFloat64
	FibreG         sql.NullFloat64
	FibreBudgetG   sql.NullFloat64
}

func UpsertNutrition(userID int64, n NutritionDay) error {
	_, err := DB.Exec(`
		INSERT INTO nutrition_days
			(user_id, date, calories, calorie_budget, protein_g, protein_budget_g,
			 carb_g, carb_budget_g, fat_g, fat_budget_g, fibre_g, fibre_budget_g, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
		ON CONFLICT(user_id, date) DO UPDATE SET
			calories=excluded.calories,
			calorie_budget=excluded.calorie_budget,
			protein_g=excluded.protein_g,
			protein_budget_g=excluded.protein_budget_g,
			carb_g=excluded.carb_g,
			carb_budget_g=excluded.carb_budget_g,
			fat_g=excluded.fat_g,
			fat_budget_g=excluded.fat_budget_g,
			fibre_g=excluded.fibre_g,
			fibre_budget_g=excluded.fibre_budget_g,
			updated_at=CURRENT_TIMESTAMP
	`, userID, n.Date, n.Calories, n.CalorieBudget, n.ProteinG, n.ProteinBudgetG,
		n.CarbG, n.CarbBudgetG, n.FatG, n.FatBudgetG, n.FibreG, n.FibreBudgetG)
	return err
}

func NutritionBetween(userID int64, from, to time.Time) (map[string]NutritionDay, error) {
	rows, err := DB.Query(`
		SELECT date, calories, calorie_budget, protein_g, protein_budget_g,
		       carb_g, carb_budget_g, fat_g, fat_budget_g, fibre_g, fibre_budget_g
		FROM nutrition_days
		WHERE user_id = ? AND date >= ? AND date <= ?
		ORDER BY date ASC
	`, userID, from.Format("2006-01-02"), to.Format("2006-01-02"))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]NutritionDay{}
	for rows.Next() {
		var n NutritionDay
		if err := rows.Scan(&n.Date, &n.Calories, &n.CalorieBudget, &n.ProteinG, &n.ProteinBudgetG,
			&n.CarbG, &n.CarbBudgetG, &n.FatG, &n.FatBudgetG, &n.FibreG, &n.FibreBudgetG); err != nil {
			return nil, err
		}
		out[n.Date] = n
	}
	return out, rows.Err()
}

func NutritionCount(userID int64) (int, error) {
	var n int
	err := DB.QueryRow(`SELECT COUNT(*) FROM nutrition_days WHERE user_id = ?`, userID).Scan(&n)
	return n, err
}
