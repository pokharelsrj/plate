package handlers

import (
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/mail"
	"os"
	"strconv"
	"strings"
	"time"

	"plate/db"
)

type userJSON struct {
	ID          int64   `json:"id"`
	Email       string  `json:"email"`
	DisplayName *string `json:"display_name"`
	Role        string  `json:"role"`
	DateOfBirth *string `json:"date_of_birth"`
	Sex         *string `json:"sex"`
	IsActive    bool    `json:"is_active"`
	CreatedAt   string  `json:"created_at"`
}

func toUserJSON(u *db.User) userJSON {
	return userJSON{
		ID:          u.ID,
		Email:       u.Email,
		DisplayName: nsPtr(u.DisplayName),
		Role:        u.Role,
		DateOfBirth: nsPtr(u.DateOfBirth),
		Sex:         nsPtr(u.Sex),
		IsActive:    u.IsActive,
		CreatedAt:   u.CreatedAt.UTC().Format(time.RFC3339),
	}
}

func nsPtr(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	s := ns.String
	return &s
}

// dummyHash is verified against when the email doesn't exist, so a miss costs
// the same PBKDF2 work as a hit and the response time stops leaking which
// addresses have accounts. The password it encodes is unguessable and unused.
const dummyHash = "pbkdf2:sha256:210000:" +
	"00000000000000000000000000000000:" +
	"0000000000000000000000000000000000000000000000000000000000000000"

// POST /api/auth/login — public
func APILogin(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if loginLimiter.blocked(ip) {
		w.Header().Set("Retry-After", strconv.Itoa(int(loginWindow.Seconds())))
		apiErr(w, http.StatusTooManyRequests, "too many failed attempts, try again later")
		return
	}

	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	u, err := db.UserByEmail(strings.TrimSpace(req.Email))
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "lookup failed")
		return
	}
	hash := dummyHash
	if u != nil {
		hash = u.PasswordHash
	}
	if !db.VerifyPassword(req.Password, hash) || u == nil || !u.IsActive {
		loginLimiter.record(ip)
		apiErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	loginLimiter.reset(ip)
	writeJSON(w, http.StatusOK, map[string]any{
		"user":    toUserJSON(u),
		"api_key": u.APIKey,
	})
}

// GET /api/health/ping — public. Also tells the app whether to offer a
// sign-up button, so it doesn't advertise something the server will refuse.
func APIPing(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":             true,
		"version":        "1.0",
		"server_time":    time.Now().UTC().Format(time.RFC3339),
		"signup_enabled": signupEnabled(),
	})
}

// signupEnabled reports whether this server accepts self-service sign-up.
// It's off unless SIGNUP_INVITE_CODE is set, so a freshly deployed server is
// never open to whoever finds it.
func signupEnabled() bool {
	return strings.TrimSpace(os.Getenv("SIGNUP_INVITE_CODE")) != ""
}

// POST /api/auth/signup — public, but only when the operator has set an
// invite code. New accounts are always role "user"; admins are made by other
// admins, never by signing up.
func APISignup(w http.ResponseWriter, r *http.Request) {
	ip := clientIP(r)
	if loginLimiter.blocked(ip) {
		w.Header().Set("Retry-After", strconv.Itoa(int(loginWindow.Seconds())))
		apiErr(w, http.StatusTooManyRequests, "too many failed attempts, try again later")
		return
	}

	want := strings.TrimSpace(os.Getenv("SIGNUP_INVITE_CODE"))
	if want == "" {
		apiErr(w, http.StatusForbidden, "sign-up is disabled on this server")
		return
	}

	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		InviteCode  string `json:"invite_code"`
		DateOfBirth string `json:"date_of_birth"`
		Sex         string `json:"sex"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}

	// Constant-time, so the code can't be recovered a character at a time.
	if subtle.ConstantTimeCompare([]byte(strings.TrimSpace(req.InviteCode)), []byte(want)) != 1 {
		loginLimiter.record(ip)
		apiErr(w, http.StatusForbidden, "invalid invite code")
		return
	}

	req.Email = strings.TrimSpace(req.Email)
	if _, err := mail.ParseAddress(req.Email); err != nil {
		apiErr(w, http.StatusBadRequest, "enter a valid email address")
		return
	}
	if len(req.Password) < 8 {
		apiErr(w, http.StatusBadRequest, "password must be at least 8 characters")
		return
	}
	if existing, _ := db.UserByEmail(req.Email); existing != nil {
		apiErr(w, http.StatusConflict, "that email already has an account")
		return
	}

	u, err := db.CreateUser(req.Email, req.Password, strings.TrimSpace(req.DisplayName),
		"user", strings.TrimSpace(req.DateOfBirth), strings.TrimSpace(req.Sex))
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "could not create the account: "+err.Error())
		return
	}
	loginLimiter.reset(ip)
	writeJSON(w, http.StatusCreated, map[string]any{
		"user":    toUserJSON(u),
		"api_key": u.APIKey,
	})
}

// DELETE /api/me — a user closing their own account. The row cascades, so
// every workout, weigh-in, health day, meal and check-in goes with it.
func APIMeDelete(w http.ResponseWriter, r *http.Request, u *db.User) {
	if err := db.DeleteUser(u.ID); err != nil {
		// The only case DeleteUser refuses is the last remaining admin,
		// which would otherwise lock everyone out of user management.
		apiErr(w, http.StatusConflict, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// GET /api/me
func APIMe(w http.ResponseWriter, r *http.Request, u *db.User) {
	writeJSON(w, http.StatusOK, toUserJSON(u))
}

// PUT /api/me
func APIMeUpdate(w http.ResponseWriter, r *http.Request, u *db.User) {
	var req struct {
		DisplayName string `json:"display_name"`
		DateOfBirth string `json:"date_of_birth"`
		Sex         string `json:"sex"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	if err := db.UpdateUserProfile(u.ID, strings.TrimSpace(req.DisplayName), strings.TrimSpace(req.DateOfBirth), strings.TrimSpace(req.Sex)); err != nil {
		apiErr(w, http.StatusInternalServerError, "update failed: "+err.Error())
		return
	}
	fresh, _ := db.UserByID(u.ID)
	writeJSON(w, http.StatusOK, toUserJSON(fresh))
}

// POST /api/me/rotate-key
func APIRotateKey(w http.ResponseWriter, r *http.Request, u *db.User) {
	key, err := db.RotateUserAPIKey(u.ID)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "rotate failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"api_key": key})
}

// GET /api/admin/users
func APIAdminListUsers(w http.ResponseWriter, r *http.Request, _ *db.User) {
	users, err := db.ListUsers()
	if err != nil {
		apiErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	out := make([]userJSON, 0, len(users))
	for i := range users {
		out = append(out, toUserJSON(&users[i]))
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": out})
}

// POST /api/admin/users
func APIAdminCreateUser(w http.ResponseWriter, r *http.Request, _ *db.User) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		Role        string `json:"role"`
		DateOfBirth string `json:"date_of_birth"`
		Sex         string `json:"sex"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	req.Email = strings.TrimSpace(req.Email)
	if req.Email == "" || req.Password == "" {
		apiErr(w, http.StatusBadRequest, "email and password required")
		return
	}
	if existing, _ := db.UserByEmail(req.Email); existing != nil {
		apiErr(w, http.StatusConflict, "email already in use")
		return
	}
	u, err := db.CreateUser(req.Email, req.Password, strings.TrimSpace(req.DisplayName), req.Role, req.DateOfBirth, req.Sex)
	if err != nil {
		apiErr(w, http.StatusInternalServerError, "create failed: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"user":    toUserJSON(u),
		"api_key": u.APIKey,
	})
}

// PUT /api/admin/users/{id}
func APIAdminUpdateUser(w http.ResponseWriter, r *http.Request, _ *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	var req struct {
		DisplayName string `json:"display_name"`
		Role        string `json:"role"`
		IsActive    *bool  `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apiErr(w, http.StatusBadRequest, "bad json")
		return
	}
	if err := db.UpdateUserAdmin(id, strings.TrimSpace(req.DisplayName), strings.TrimSpace(req.Role), req.IsActive); err != nil {
		apiErr(w, http.StatusInternalServerError, "update failed: "+err.Error())
		return
	}
	fresh, _ := db.UserByID(id)
	if fresh == nil {
		apiErr(w, http.StatusNotFound, "user not found")
		return
	}
	writeJSON(w, http.StatusOK, toUserJSON(fresh))
}

// POST /api/admin/users/{id}/reset-password
func APIAdminResetPassword(w http.ResponseWriter, r *http.Request, _ *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Password == "" {
		apiErr(w, http.StatusBadRequest, "password required")
		return
	}
	if err := db.SetUserPassword(id, req.Password); err != nil {
		apiErr(w, http.StatusInternalServerError, "reset failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/admin/users/{id}
func APIAdminDeleteUser(w http.ResponseWriter, r *http.Request, u *db.User) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		apiErr(w, http.StatusBadRequest, "bad id")
		return
	}
	if err := db.DeleteUser(id); err != nil {
		apiErr(w, http.StatusConflict, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
