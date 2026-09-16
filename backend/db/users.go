package db

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

type User struct {
	ID           int64
	Email        string
	DisplayName  sql.NullString
	PasswordHash string
	APIKey       string
	Role         string
	DateOfBirth  sql.NullString
	Sex          sql.NullString
	IsActive     bool
	CreatedAt    time.Time
}

func (u *User) IsAdmin() bool { return u.Role == "admin" }

const pbkdf2Iterations = 210_000

// HashPassword derives a PBKDF2-SHA256 hash in the form
// pbkdf2:sha256:<iterations>:<salt-hex>:<key-hex>.
func HashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, pbkdf2Iterations, 32)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("pbkdf2:sha256:%d:%s:%s",
		pbkdf2Iterations, hex.EncodeToString(salt), hex.EncodeToString(key)), nil
}

// VerifyPassword checks a plaintext password against a stored hash.
func VerifyPassword(password, stored string) bool {
	parts := strings.Split(stored, ":")
	if len(parts) != 5 || parts[0] != "pbkdf2" || parts[1] != "sha256" {
		return false
	}
	iter, err := strconv.Atoi(parts[2])
	if err != nil {
		return false
	}
	salt, err := hex.DecodeString(parts[3])
	if err != nil {
		return false
	}
	want, err := hex.DecodeString(parts[4])
	if err != nil {
		return false
	}
	got, err := pbkdf2.Key(sha256.New, password, salt, iter, len(want))
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(got, want) == 1
}

// NewAPIKey returns a random 32-byte hex string.
func NewAPIKey() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}

const userCols = `id, email, display_name, password_hash, api_key, role, date_of_birth, sex, is_active, created_at`

func scanUser(row interface{ Scan(...any) error }) (*User, error) {
	var u User
	err := row.Scan(&u.ID, &u.Email, &u.DisplayName, &u.PasswordHash, &u.APIKey,
		&u.Role, &u.DateOfBirth, &u.Sex, &u.IsActive, &u.CreatedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func UserByEmail(email string) (*User, error) {
	return scanUser(DB.QueryRow(`SELECT `+userCols+` FROM users WHERE email = ? COLLATE NOCASE`, email))
}

func UserByAPIKey(key string) (*User, error) {
	return scanUser(DB.QueryRow(`SELECT `+userCols+` FROM users WHERE api_key = ?`, key))
}

func UserByID(id int64) (*User, error) {
	return scanUser(DB.QueryRow(`SELECT `+userCols+` FROM users WHERE id = ?`, id))
}

func ListUsers() ([]User, error) {
	rows, err := DB.Query(`SELECT ` + userCols + ` FROM users ORDER BY id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Email, &u.DisplayName, &u.PasswordHash, &u.APIKey,
			&u.Role, &u.DateOfBirth, &u.Sex, &u.IsActive, &u.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func CreateUser(email, password, displayName, role, dob, sex string) (*User, error) {
	hash, err := HashPassword(password)
	if err != nil {
		return nil, err
	}
	if role != "admin" {
		role = "user"
	}
	res, err := DB.Exec(`
		INSERT INTO users (email, display_name, password_hash, api_key, role, date_of_birth, sex)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	`, email, nullStr(displayName), hash, NewAPIKey(), role, nullStr(dob), nullStr(sex))
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	return UserByID(id)
}

// UpdateUserProfile updates display name / dob / sex; empty strings leave the field unchanged.
func UpdateUserProfile(id int64, displayName, dob, sex string) error {
	_, err := DB.Exec(`
		UPDATE users SET
			display_name  = COALESCE(?, display_name),
			date_of_birth = COALESCE(?, date_of_birth),
			sex           = COALESCE(?, sex)
		WHERE id = ?
	`, nullStr(displayName), nullStr(dob), nullStr(sex), id)
	return err
}

func UpdateUserAdmin(id int64, displayName, role string, isActive *bool) error {
	var active any
	if isActive != nil {
		active = *isActive
	}
	if role != "" && role != "admin" {
		role = "user"
	}
	_, err := DB.Exec(`
		UPDATE users SET
			display_name = COALESCE(?, display_name),
			role         = COALESCE(?, role),
			is_active    = COALESCE(?, is_active)
		WHERE id = ?
	`, nullStr(displayName), nullStr(role), active, id)
	return err
}

func SetUserPassword(id int64, password string) error {
	hash, err := HashPassword(password)
	if err != nil {
		return err
	}
	_, err = DB.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, hash, id)
	return err
}

func RotateUserAPIKey(id int64) (string, error) {
	key := NewAPIKey()
	_, err := DB.Exec(`UPDATE users SET api_key = ? WHERE id = ?`, key, id)
	return key, err
}

func DeleteUser(id int64) error {
	u, err := UserByID(id)
	if err != nil {
		return err
	}
	if u == nil {
		return fmt.Errorf("user not found")
	}
	if u.IsAdmin() {
		var admins int
		if err := DB.QueryRow(`SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = 1`).Scan(&admins); err != nil {
			return err
		}
		if admins <= 1 {
			return fmt.Errorf("cannot delete the only admin")
		}
	}
	_, err = DB.Exec(`DELETE FROM users WHERE id = ?`, id)
	return err
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

// SeedAdminFromEnv creates the initial admin account from the legacy env vars
// (AUTH_USER / AUTH_PASS / HEALTH_API_KEY / USER_DOB) when the users table is empty.
func SeedAdminFromEnv() error {
	var n int
	if err := DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return nil
	}
	email := os.Getenv("AUTH_USER")
	pass := os.Getenv("AUTH_PASS")
	if email == "" || pass == "" {
		log.Println("users table empty and AUTH_USER/AUTH_PASS not set — skipping admin seed")
		return nil
	}
	hash, err := HashPassword(pass)
	if err != nil {
		return err
	}
	apiKey := os.Getenv("HEALTH_API_KEY")
	if apiKey == "" {
		apiKey = NewAPIKey()
	}
	_, err = DB.Exec(`
		INSERT INTO users (email, display_name, password_hash, api_key, role, date_of_birth)
		VALUES (?, ?, ?, ?, 'admin', ?)
	`, email, nullStr("Admin"), hash, apiKey, nullStr(os.Getenv("USER_DOB")))
	if err == nil {
		log.Printf("seeded admin user %q from env", email)
	}
	return err
}
