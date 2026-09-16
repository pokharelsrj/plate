package sync

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"plate/db"
)

func basicAuth(user, pass string) string {
	return "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+pass))
}

const lafBase = "https://publicapi.lafitness.com/LAF_S4.7.15/Services"

type lafClient struct {
	OSName         string `json:"OSName"`
	Version        string `json:"Version"`
	BrandID        string `json:"BrandID"`
	OSVersion      string `json:"OSVersion"`
	VariantId      string `json:"VariantId"`
	MacAddress     string `json:"MacAddress"`
	Model          string `json:"Model"`
	TimezoneOffset string `json:"TimezoneOffset"`
	Platform       string `json:"Platform"`
	DeviceID       string `json:"DeviceID"`
}

func defaultLafClient() lafClient {
	return lafClient{
		OSName: "iPhone", Version: "4.6.9", BrandID: "1", OSVersion: "26.5",
		VariantId: "841", MacAddress: "02:00:00:00:00:00", Model: "iPhone18,2",
		TimezoneOffset: "-4", Platform: "iOS",
		DeviceID: "9DF9668C-7D9C-4809-9204-882D03F078F0",
	}
}

type lafAuthResp struct {
	Success bool   `json:"Success"`
	Message string `json:"Message"`
	Value   string `json:"Value"`
}

type lafCheckinResp struct {
	Success bool   `json:"Success"`
	Message string `json:"Message"`
	Value   []struct {
		CheckLogID int64  `json:"CheckLogID"`
		ClubID     int    `json:"Club_ID"`
		DateStr    string `json:"DateStr"`
	} `json:"Value"`
}

func authenticateLaf(ctx context.Context, user, pass string) (string, error) {
	body := map[string]any{
		"request": map[string]any{
			"Value":  map[string]string{"Username": user, "Password": pass},
			"Client": defaultLafClient(),
		},
	}
	buf, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, "POST",
		lafBase+"/Public.svc/AuthenticateAccount", bytes.NewReader(buf))
	req.Header.Set("Content-Type", "application/json")
	req.Header["ver"] = []string{"4.6.0a"}
	req.Header.Set("User-Agent", "LA Fitness/4.6.9 (iPhone; iOS 26.5; Scale/3.00)")
	req.Header.Set("Authorization", basicAuth(user, pass))

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("auth http: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("auth status %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var a lafAuthResp
	if err := json.Unmarshal(raw, &a); err != nil {
		return "", fmt.Errorf("auth decode: %w", err)
	}
	if !a.Success {
		return "", fmt.Errorf("auth failed: %s", a.Message)
	}
	// Value is "<expiry>|<token>"
	idx := strings.Index(a.Value, "|")
	if idx < 0 || idx == len(a.Value)-1 {
		return "", errors.New("auth: missing token in Value")
	}
	return a.Value[idx+1:], nil
}

func fetchCheckins(ctx context.Context, token, user, pass string, from, to time.Time) ([]db.GymCheckin, error) {
	body := map[string]any{
		"request": map[string]any{
			"Value": map[string]string{
				"FromDate": from.Format("2006-01-02"),
				"ToDate":   to.Format("2006-01-02"),
			},
			"Client": defaultLafClient(),
		},
	}
	buf, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, "POST",
		lafBase+"/Private.svc/GetCheckinHistory", bytes.NewReader(buf))
	req.Header.Set("Content-Type", "application/json")
	req.Header["ver"] = []string{"4.6.0a"}
	req.Header.Set("User-Agent", "LA Fitness/4.6.9 (iPhone; iOS 26.5; Scale/3.00)")
	req.Header.Set("AuthToken", token)
	req.Header.Set("Authorization", basicAuth(user, pass))

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("checkins http: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("checkins status %d: %s", resp.StatusCode, truncate(string(raw), 200))
	}
	var r lafCheckinResp
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, fmt.Errorf("checkins decode: %w", err)
	}
	if !r.Success {
		return nil, fmt.Errorf("checkins failed: %s", r.Message)
	}

	loc := time.Local
	out := make([]db.GymCheckin, 0, len(r.Value))
	for _, v := range r.Value {
		t, err := time.ParseInLocation("01/02/2006 03:04:05 PM", v.DateStr, loc)
		if err != nil {
			continue
		}
		out = append(out, db.GymCheckin{
			CheckinID: v.CheckLogID,
			ClubID:    v.ClubID,
			CheckinAt: t,
		})
	}
	return out, nil
}

func SyncLAFitness(ctx context.Context, userID int64, daysBack int) (int, error) {
	user := os.Getenv("LAFITNESS_USER")
	pass := os.Getenv("LAFITNESS_PASS")
	if user == "" || pass == "" {
		return 0, errors.New("LAFITNESS_USER/LAFITNESS_PASS not set")
	}
	token, err := authenticateLaf(ctx, user, pass)
	if err != nil {
		return 0, err
	}
	to := time.Now()
	from := to.AddDate(0, 0, -daysBack)
	checkins, err := fetchCheckins(ctx, token, user, pass, from, to)
	if err != nil {
		return 0, err
	}
	count := 0
	for _, c := range checkins {
		if err := db.UpsertCheckin(userID, c); err != nil {
			return count, fmt.Errorf("upsert checkin %d: %w", c.CheckinID, err)
		}
		count++
	}
	return count, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
