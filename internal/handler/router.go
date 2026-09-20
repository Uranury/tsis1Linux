package handler

import (
	"net/http"

	"github.com/Uranury/tsis1Linux/internal/auth"
)

func NewRouter(authH *AuthHandler, taskH *TaskHandler, jwtIssuer *auth.JWTIssuer) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /auth/register", authH.Register)
	mux.HandleFunc("POST /auth/login", authH.Login)
	mux.HandleFunc("POST /auth/refresh", authH.Refresh)
	mux.HandleFunc("POST /auth/logout", authH.Logout)
	mux.HandleFunc("POST /auth/logout-all", requireAuth(jwtIssuer, authH.LogoutAll))

	mux.HandleFunc("POST /tasks", requireAuth(jwtIssuer, taskH.Create))
	mux.HandleFunc("GET /tasks", requireAuth(jwtIssuer, taskH.List))
	mux.HandleFunc("GET /tasks/{id}", requireAuth(jwtIssuer, taskH.Get))
	mux.HandleFunc("PUT /tasks/{id}", requireAuth(jwtIssuer, taskH.Update))
	mux.HandleFunc("DELETE /tasks/{id}", requireAuth(jwtIssuer, taskH.Delete))

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	return mux
}
