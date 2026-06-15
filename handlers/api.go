package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"os"

	"pi-webpage/db"
)

func nfPtr(nf sql.NullFloat64) *float64 {
	if !nf.Valid {
		return nil
	}
	v := nf.Float64
	return &v
}

func niPtr(ni sql.NullInt64) *int64 {
	if !ni.Valid {
		return nil
	}
	v := ni.Int64
	return &v
}

// apiHandler is an endpoint that requires a valid X-Api-Key.
type apiHandler func(w http.ResponseWriter, r *http.Request, u *db.User)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func apiErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// apiUser resolves the request's user from the X-Api-Key header.
// Falls back to the legacy HEALTH_API_KEY env var (resolves to the first admin)
// so the existing iOS Shortcut keeps working on databases seeded before users existed.
func apiUser(r *http.Request) *db.User {
	key := r.Header.Get("X-Api-Key")
	if key == "" {
		return nil
	}
	u, err := db.UserByAPIKey(key)
	if err != nil || u == nil || !u.IsActive {
		if legacy := os.Getenv("HEALTH_API_KEY"); legacy != "" && key == legacy {
			if admin, _ := db.UserByEmail(os.Getenv("AUTH_USER")); admin != nil && admin.IsActive {
				return admin
			}
		}
		return nil
	}
	return u
}

// withAPIKey wraps an apiHandler with X-Api-Key auth.
func WithAPIKey(h apiHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := apiUser(r)
		if u == nil {
			apiErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		h(w, r, u)
	}
}

// withAdmin additionally requires the user to be an admin.
func WithAdmin(h apiHandler) http.HandlerFunc {
	return WithAPIKey(func(w http.ResponseWriter, r *http.Request, u *db.User) {
		if !u.IsAdmin() {
			apiErr(w, http.StatusForbidden, "admin only")
			return
		}
		h(w, r, u)
	})
}
