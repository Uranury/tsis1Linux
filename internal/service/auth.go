package service

import (
	"context"
	"errors"
	"time"

	"github.com/Uranury/tsis1Linux/internal/auth"
	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/internal/repo"
	"github.com/Uranury/tsis1Linux/pkg/dbutil"
	"github.com/google/uuid"
)

var (
	ErrInvalidCredentials = errors.New("service: invalid email or password")
	ErrEmailTaken         = errors.New("service: email already registered")
	ErrInvalidRefresh     = errors.New("service: invalid or expired refresh token")
)

// TokenPair is what login/refresh hand back to the client: a short-lived
// JWT for authenticating requests and an opaque refresh token for getting
// a new one once it expires.
type TokenPair struct {
	AccessToken  string
	RefreshToken string
}

type AuthService struct {
	users         repo.User
	refreshTokens repo.RefreshToken
	txProvider    dbutil.TxProvider
	jwt           *auth.JWTIssuer
	refreshTTL    time.Duration
}

func NewAuthService(users repo.User, refreshTokens repo.RefreshToken, txProvider dbutil.TxProvider, jwt *auth.JWTIssuer, refreshTTL time.Duration) *AuthService {
	return &AuthService{
		users:         users,
		refreshTokens: refreshTokens,
		txProvider:    txProvider,
		jwt:           jwt,
		refreshTTL:    refreshTTL,
	}
}

func (s *AuthService) Register(ctx context.Context, username, email, password string) (*models.User, error) {
	if _, err := s.users.GetByEmail(ctx, email); err == nil {
		return nil, ErrEmailTaken
	} else if !errors.Is(err, repo.ErrNotFound) {
		return nil, err
	}

	hash, err := auth.HashPassword(password)
	if err != nil {
		return nil, err
	}

	id := uuid.New()
	if err := s.users.Create(ctx, id, username, email, hash); err != nil {
		return nil, err
	}
	return s.users.GetByID(ctx, id)
}

func (s *AuthService) Login(ctx context.Context, email, password string) (*TokenPair, error) {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, repo.ErrNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}
	if !auth.CheckPassword(u.Password, password) {
		return nil, ErrInvalidCredentials
	}
	return s.issueTokenPair(ctx, u.ID)
}

// Refresh rotates the refresh token: the presented one is revoked and a new
// pair is issued. This limits the damage of a leaked refresh token to a
// single use before it stops working.
//
// The revoke-old/create-new pair runs inside a transaction so the two
// writes succeed or fail together — without it, a failure between them
// could revoke the caller's only refresh token without ever handing back
// its replacement, locking them out.
func (s *AuthService) Refresh(ctx context.Context, rawRefreshToken string) (*TokenPair, error) {
	hash := auth.HashRefreshToken(rawRefreshToken)
	rt, err := s.refreshTokens.GetByHash(ctx, hash)
	if err != nil {
		if errors.Is(err, repo.ErrNotFound) {
			return nil, ErrInvalidRefresh
		}
		return nil, err
	}
	if rt.RevokedAt != nil || time.Now().After(rt.ExpiresAt) {
		return nil, ErrInvalidRefresh
	}

	access, err := s.jwt.IssueAccessToken(rt.UserID)
	if err != nil {
		return nil, err
	}
	rawNewRefresh, err := auth.NewRefreshToken()
	if err != nil {
		return nil, err
	}
	newExpiry := time.Now().Add(s.refreshTTL)

	err = s.txProvider.RunInTx(ctx, func(exec dbutil.Executor) error {
		tokens := repo.NewRefreshToken(exec)
		if err := tokens.Revoke(ctx, rt.ID); err != nil {
			return err
		}
		_, err := tokens.Create(ctx, rt.UserID, auth.HashRefreshToken(rawNewRefresh), newExpiry)
		return err
	})
	if err != nil {
		return nil, err
	}

	return &TokenPair{AccessToken: access, RefreshToken: rawNewRefresh}, nil
}

// Logout revokes the refresh token so it can no longer be used. It is
// idempotent: an already-invalid token is not an error.
func (s *AuthService) Logout(ctx context.Context, rawRefreshToken string) error {
	hash := auth.HashRefreshToken(rawRefreshToken)
	rt, err := s.refreshTokens.GetByHash(ctx, hash)
	if err != nil {
		if errors.Is(err, repo.ErrNotFound) {
			return nil
		}
		return err
	}
	return s.refreshTokens.Revoke(ctx, rt.ID)
}

// LogoutAll revokes every refresh token issued to userID — "log out
// everywhere." Already-issued access tokens keep working until they
// expire on their own since they're stateless JWTs, not looked up per
// request.
func (s *AuthService) LogoutAll(ctx context.Context, userID uuid.UUID) error {
	return s.refreshTokens.RevokeAllForUser(ctx, userID)
}

func (s *AuthService) issueTokenPair(ctx context.Context, userID uuid.UUID) (*TokenPair, error) {
	access, err := s.jwt.IssueAccessToken(userID)
	if err != nil {
		return nil, err
	}

	rawRefresh, err := auth.NewRefreshToken()
	if err != nil {
		return nil, err
	}
	_, err = s.refreshTokens.Create(ctx, userID, auth.HashRefreshToken(rawRefresh), time.Now().Add(s.refreshTTL))
	if err != nil {
		return nil, err
	}

	return &TokenPair{AccessToken: access, RefreshToken: rawRefresh}, nil
}
