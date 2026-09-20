package repo

import (
	"context"
	"errors"

	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/pkg/dbutil"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type Task interface {
	Create(ctx context.Context, t *models.Task) error
	GetByID(ctx context.Context, id uuid.UUID) (*models.Task, error)
	ListByUser(ctx context.Context, userID uuid.UUID) ([]models.Task, error)
	Update(ctx context.Context, t *models.Task) error
	Delete(ctx context.Context, id uuid.UUID) error
}

type task struct {
	exec dbutil.Executor
}

func NewTask(exec dbutil.Executor) Task {
	return &task{exec: exec}
}

func (t *task) Create(ctx context.Context, m *models.Task) error {
	return t.exec.QueryRow(ctx,
		`INSERT INTO tasks (user_id, title, details, status)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, created_at, updated_at`,
		m.UserID, m.Title, m.Details, m.Status,
	).Scan(&m.ID, &m.CreatedAt, &m.UpdatedAt)
}

func (t *task) GetByID(ctx context.Context, id uuid.UUID) (*models.Task, error) {
	var m models.Task
	err := t.exec.QueryRow(ctx,
		`SELECT id, user_id, title, details, status, created_at, updated_at
		 FROM tasks WHERE id = $1`, id,
	).Scan(&m.ID, &m.UserID, &m.Title, &m.Details, &m.Status, &m.CreatedAt, &m.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

func (t *task) ListByUser(ctx context.Context, userID uuid.UUID) ([]models.Task, error) {
	rows, err := t.exec.Query(ctx,
		`SELECT id, user_id, title, details, status, created_at, updated_at
		 FROM tasks WHERE user_id = $1 ORDER BY created_at DESC`, userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tasks []models.Task
	for rows.Next() {
		var m models.Task
		if err := rows.Scan(&m.ID, &m.UserID, &m.Title, &m.Details, &m.Status, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		tasks = append(tasks, m)
	}
	return tasks, rows.Err()
}

func (t *task) Update(ctx context.Context, m *models.Task) error {
	tag, err := t.exec.Exec(ctx,
		`UPDATE tasks SET title = $1, details = $2, status = $3, updated_at = now()
		 WHERE id = $4 AND user_id = $5`,
		m.Title, m.Details, m.Status, m.ID, m.UserID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (t *task) Delete(ctx context.Context, id uuid.UUID) error {
	tag, err := t.exec.Exec(ctx, "DELETE FROM tasks WHERE id = $1", id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
