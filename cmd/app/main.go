package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/Uranury/tsis1Linux/internal/auth"
	"github.com/Uranury/tsis1Linux/internal/config"
	"github.com/Uranury/tsis1Linux/internal/db"
	"github.com/Uranury/tsis1Linux/internal/handler"
	"github.com/Uranury/tsis1Linux/internal/repo"
	"github.com/Uranury/tsis1Linux/internal/service"
	"github.com/Uranury/tsis1Linux/pkg/dbutil"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	if err := db.Migrate(cfg.DatabaseURL); err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		return err
	}

	userRepo := repo.NewUser(pool)
	taskRepo := repo.NewTask(pool)
	refreshTokenRepo := repo.NewRefreshToken(pool)
	txProvider := dbutil.NewTxProvider(pool)

	jwtIssuer := auth.NewJWTIssuer(cfg.JWTSecret, cfg.AccessTokenTTL)

	authService := service.NewAuthService(userRepo, refreshTokenRepo, txProvider, jwtIssuer, cfg.RefreshTokenTTL)
	taskService := service.NewTaskService(taskRepo)

	authHandler := handler.NewAuthHandler(authService)
	taskHandler := handler.NewTaskHandler(taskService)

	router := handler.NewRouter(authHandler, taskHandler, jwtIssuer)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() {
		log.Printf("listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
			return
		}
		serveErr <- nil
	}()

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
		log.Println("shutting down")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
