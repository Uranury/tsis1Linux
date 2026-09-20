package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
)

// NewRefreshToken returns a random, URL-safe opaque token. This is the raw
// value handed to the client — only its hash (HashRefreshToken) is stored.
func NewRefreshToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// HashRefreshToken deterministically hashes a raw refresh token for storage
// and lookup. SHA-256 (not bcrypt) is correct here: the token is already
// high-entropy random data, not a low-entropy user-chosen password, so a
// fast, deterministic hash that supports exact-match lookup by hash is what
// we want — bcrypt is neither deterministic nor practical to index on.
func HashRefreshToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
