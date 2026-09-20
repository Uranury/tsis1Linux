package repo

import (
	"context"
	"errors"
	"time"

	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/pkg/dbutil"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type RefreshToken interface {
	Create(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) (*models.RefreshToken, error)
	GetByHash(ctx context.Context, tokenHash string) (*models.RefreshToken, error)
	Revoke(ctx context.Context, id uuid.UUID) error
	RevokeAllForUser(ctx context.Context, userID uuid.UUID) error
}

type refreshToken struct {
	exec dbutil.Executor
}

func NewRefreshToken(exec dbutil.Executor) RefreshToken {
	return &refreshToken{exec: exec}
}

func (r *refreshToken) Create(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) (*models.RefreshToken, error) {
	m := &models.RefreshToken{
		UserID:    userID,
		TokenHash: tokenHash,
		ExpiresAt: expiresAt,
	}
	err := r.exec.QueryRow(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		 VALUES ($1, $2, $3)
		 RETURNING id, created_at`,
		userID, tokenHash, expiresAt,
	).Scan(&m.ID, &m.CreatedAt)
	if err != nil {
		return nil, err
	}
	return m, nil
}

func (r *refreshToken) GetByHash(ctx context.Context, tokenHash string) (*models.RefreshToken, error) {
	var m models.RefreshToken
	err := r.exec.QueryRow(ctx,
		`SELECT id, user_id, token_hash, expires_at, revoked_at, created_at
		 FROM refresh_tokens WHERE token_hash = $1`, tokenHash,
	).Scan(&m.ID, &m.UserID, &m.TokenHash, &m.ExpiresAt, &m.RevokedAt, &m.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

func (r *refreshToken) Revoke(ctx context.Context, id uuid.UUID) error {
	_, err := r.exec.Exec(ctx, "UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL", id)
	return err
}

func (r *refreshToken) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.exec.Exec(ctx, "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL", userID)
	return err
}
