package repo

import (
	"context"
	"errors"

	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/pkg/dbutil"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var ErrNotFound = errors.New("repo: not found")

type User interface {
	GetByID(ctx context.Context, id uuid.UUID) (*models.User, error)
	GetByEmail(ctx context.Context, email string) (*models.User, error)
	Create(ctx context.Context, id uuid.UUID, username, email, password string) error
}

type user struct {
	exec dbutil.Executor
}

func NewUser(exec dbutil.Executor) User {
	return &user{exec: exec}
}

func (u *user) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	var usr models.User
	err := u.exec.QueryRow(ctx, "SELECT id, username, email, password, created_at, updated_at FROM users WHERE id = $1", id).
		Scan(&usr.ID, &usr.Username, &usr.Email, &usr.Password, &usr.CreatedAt, &usr.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &usr, nil
}

func (u *user) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	var usr models.User
	err := u.exec.QueryRow(ctx, "SELECT id, username, email, password, created_at, updated_at FROM users WHERE email = $1", email).
		Scan(&usr.ID, &usr.Username, &usr.Email, &usr.Password, &usr.CreatedAt, &usr.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &usr, nil
}

func (u *user) Create(ctx context.Context, id uuid.UUID, username, email, password string) error {
	_, err := u.exec.Exec(ctx, "INSERT INTO users (id, username, email, password) VALUES ($1, $2, $3, $4)", id, username, email, password)
	return err
}
