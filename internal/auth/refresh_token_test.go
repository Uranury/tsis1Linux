package auth

import "testing"

func TestNewRefreshTokenIsUniqueAndNonEmpty(t *testing.T) {
	a, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken: %v", err)
	}
	b, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken: %v", err)
	}
	if a == "" || b == "" {
		t.Fatal("NewRefreshToken returned an empty token")
	}
	if a == b {
		t.Error("two calls to NewRefreshToken returned the same token")
	}
}

func TestHashRefreshTokenIsDeterministic(t *testing.T) {
	raw, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken: %v", err)
	}
	h1 := HashRefreshToken(raw)
	h2 := HashRefreshToken(raw)
	if h1 != h2 {
		t.Error("HashRefreshToken is not deterministic")
	}
	if h1 == raw {
		t.Error("HashRefreshToken returned the raw token unchanged")
	}
}
