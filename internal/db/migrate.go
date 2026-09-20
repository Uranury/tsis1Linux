// Package db wires up the database connection pool and applies schema
// migrations. The migration SQL files are embedded into the binary at
// compile time (see migrations.FS) rather than read from disk, so
// deployment doesn't need to ship the migrations/ directory.
package db

import (
	"errors"
	"fmt"
	"strings"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"

	"github.com/Uranury/tsis1Linux/migrations"
)

// Migrate applies all pending "up" migrations against databaseURL. It is a
// no-op (not an error) if the schema is already at the latest version.
func Migrate(databaseURL string) (err error) {
	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return fmt.Errorf("db: init migration source: %w", err)
	}

	m, err := migrate.NewWithSourceInstance("iofs", src, toMigrateDSN(databaseURL))
	if err != nil {
		return fmt.Errorf("db: init migrator: %w", err)
	}
	defer func() {
		// Close returns the source and database driver's close errors
		// separately; only surface them if Up itself didn't already fail.
		if srcErr, dbErr := m.Close(); err == nil {
			err = errors.Join(srcErr, dbErr)
		}
	}()

	if upErr := m.Up(); upErr != nil && !errors.Is(upErr, migrate.ErrNoChange) {
		return fmt.Errorf("db: apply migrations: %w", upErr)
	}
	return nil
}

// toMigrateDSN rewrites a standard postgres:// / postgresql:// connection
// string to the pgx5:// scheme golang-migrate's pgx driver expects.
func toMigrateDSN(databaseURL string) string {
	for _, prefix := range []string{"postgres://", "postgresql://"} {
		if strings.HasPrefix(databaseURL, prefix) {
			return "pgx5://" + strings.TrimPrefix(databaseURL, prefix)
		}
	}
	return databaseURL
}
