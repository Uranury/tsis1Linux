package dbutil

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TxProvider interface {
	RunInTx(ctx context.Context, fn func(Executor) error) error
}

type txProvider struct {
	db *pgxpool.Pool
}

func NewTxProvider(db *pgxpool.Pool) TxProvider {
	return &txProvider{
		db: db,
	}
}

func (t *txProvider) RunInTx(ctx context.Context, fn func(Executor) error) error {
	tx, err := t.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
