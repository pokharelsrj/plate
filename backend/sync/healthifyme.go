package sync

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"time"

	"plate/db"
)

type hmeInsightsResp struct {
	InsightsSections []struct {
		InsightCards []struct {
			CardType   string         `json:"card_type"`
			Parameters map[string]any `json:"parameters"`
		} `json:"insight_cards"`
	} `json:"insights_sections"`
}

func fetchHealthifyDay(ctx context.Context, apiKey, userID, date string) (*db.NutritionDay, error) {
	u := url.URL{
		Scheme: "https",
		Host:   "api.healthifyme.com",
		Path:   "/api/v2/insights/insights_page",
	}
	q := u.Query()
	q.Set("format", "json")
	q.Set("ios_vc", "1193")
	q.Set("auth_user_id", userID)
	q.Set("date", date)
	u.RawQuery = q.Encode()

	req, _ := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	req.Header.Set("Authorization", "ApiKey "+apiKey)
	req.Header.Set("User-Agent", "HealthifyMe/11.9.3 (iPhone; iOS 26.5; Scale/3.00)")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("hme http: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("hme status %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var r hmeInsightsResp
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("hme decode: %w", err)
	}

	for _, sec := range r.InsightsSections {
		for _, c := range sec.InsightCards {
			if c.CardType != "pfcf-card" {
				continue
			}
			return parsePFCFCard(date, c.Parameters), nil
		}
	}
	// No pfcf-card found for this date (no meals logged) — store row with nulls
	return &db.NutritionDay{Date: date}, nil
}

func parsePFCFCard(date string, p map[string]any) *db.NutritionDay {
	n := &db.NutritionDay{Date: date}
	n.Calories = nullFloat(p["calorie_consumed"])
	n.CalorieBudget = nullFloat(p["calorie_budget"])
	n.ProteinG = nullFloat(p["protein"])
	n.ProteinBudgetG = nullFloat(p["protein_budget"])
	n.CarbG = nullFloat(p["carb"])
	n.CarbBudgetG = nullFloat(p["carb_budget"])
	n.FatG = nullFloat(p["fat"])
	n.FatBudgetG = nullFloat(p["fat_budget"])
	n.FibreG = nullFloat(p["fibre"])
	n.FibreBudgetG = nullFloat(p["fibre_budget"])
	return n
}

func nullFloat(v any) sql.NullFloat64 {
	if v == nil {
		return sql.NullFloat64{}
	}
	f, ok := v.(float64)
	if !ok {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: f, Valid: true}
}

func SyncHealthifyme(ctx context.Context, daysBack int) (int, error) {
	apiKey := os.Getenv("HEALTHIFYME_API_KEY")
	userID := os.Getenv("HEALTHIFYME_USER_ID")
	if apiKey == "" || userID == "" {
		return 0, errors.New("HEALTHIFYME_API_KEY/HEALTHIFYME_USER_ID not set")
	}
	today := time.Now()
	count := 0
	var firstErr error
	for i := 0; i <= daysBack; i++ {
		d := today.AddDate(0, 0, -i).Format("2006-01-02")
		select {
		case <-ctx.Done():
			return count, ctx.Err()
		default:
		}
		n, err := fetchHealthifyDay(ctx, apiKey, userID, d)
		if err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("date %s: %w", d, err)
			}
			continue
		}
		if err := db.UpsertNutrition(*n); err != nil {
			if firstErr == nil {
				firstErr = fmt.Errorf("upsert %s: %w", d, err)
			}
			continue
		}
		count++
		if i < daysBack {
			time.Sleep(500 * time.Millisecond)
		}
	}
	if count == 0 && firstErr != nil {
		return 0, firstErr
	}
	return count, nil
}
