package auth

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestJWTIssuerRoundTrip(t *testing.T) {
	issuer := NewJWTIssuer("test-secret", time.Minute)
	userID := uuid.New()

	token, err := issuer.IssueAccessToken(userID)
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}

	claims, err := issuer.ParseAccessToken(token)
	if err != nil {
		t.Fatalf("ParseAccessToken: %v", err)
	}
	if claims.UserID != userID {
		t.Errorf("UserID = %s, want %s", claims.UserID, userID)
	}
}

func TestJWTIssuerRejectsExpired(t *testing.T) {
	issuer := NewJWTIssuer("test-secret", -time.Minute) // already expired
	token, err := issuer.IssueAccessToken(uuid.New())
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}

	if _, err := issuer.ParseAccessToken(token); err == nil {
		t.Error("ParseAccessToken accepted an expired token")
	}
}

func TestJWTIssuerRejectsWrongSecret(t *testing.T) {
	issuer := NewJWTIssuer("test-secret", time.Minute)
	token, err := issuer.IssueAccessToken(uuid.New())
	if err != nil {
		t.Fatalf("IssueAccessToken: %v", err)
	}

	other := NewJWTIssuer("different-secret", time.Minute)
	if _, err := other.ParseAccessToken(token); err == nil {
		t.Error("ParseAccessToken accepted a token signed with a different secret")
	}
}
