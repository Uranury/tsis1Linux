package handler

import (
	"context"
	"net/http"
	"strings"

	"github.com/Uranury/tsis1Linux/internal/auth"
)

// requireAuth wraps next so it only runs when the request carries a valid
// "Authorization: Bearer <jwt>" header, injecting the user ID into the
// request context for handlers to read via userIDFromContext.
func requireAuth(jwtIssuer *auth.JWTIssuer, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		raw, ok := strings.CutPrefix(header, "Bearer ")
		if !ok || raw == "" {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}

		claims, err := jwtIssuer.ParseAccessToken(raw)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid or expired token")
			return
		}

		ctx := context.WithValue(r.Context(), userIDKey, claims.UserID)
		next(w, r.WithContext(ctx))
	}
}
