package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"pi-webpage/db"
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

// POST /api/auth/login — public
func APILogin(w http.ResponseWriter, r *http.Request) {
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
	if u == nil || !u.IsActive || !db.VerifyPassword(req.Password, u.PasswordHash) {
		apiErr(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":    toUserJSON(u),
		"api_key": u.APIKey,
	})
}

// GET /api/health/ping — public
func APIPing(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":          true,
		"version":     "1.0",
		"server_time": time.Now().UTC().Format(time.RFC3339),
	})
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
