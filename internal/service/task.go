package service

import (
	"context"
	"errors"

	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/internal/repo"
	"github.com/google/uuid"
)

// ErrForbidden is returned when a task exists but doesn't belong to the
// requesting user — surfaced by handlers as 404, not 403, so as not to leak
// whether the ID belongs to someone else.
var ErrForbidden = errors.New("service: task does not belong to user")

type TaskService struct {
	tasks repo.Task
}

func NewTaskService(tasks repo.Task) *TaskService {
	return &TaskService{tasks: tasks}
}

func (s *TaskService) Create(ctx context.Context, userID uuid.UUID, title string, details *string) (*models.Task, error) {
	t := &models.Task{
		UserID:  userID,
		Title:   title,
		Details: details,
		Status:  models.Pending,
	}
	if err := s.tasks.Create(ctx, t); err != nil {
		return nil, err
	}
	return t, nil
}

func (s *TaskService) List(ctx context.Context, userID uuid.UUID) ([]models.Task, error) {
	return s.tasks.ListByUser(ctx, userID)
}

func (s *TaskService) Get(ctx context.Context, userID, taskID uuid.UUID) (*models.Task, error) {
	t, err := s.tasks.GetByID(ctx, taskID)
	if err != nil {
		return nil, err
	}
	if t.UserID != userID {
		return nil, ErrForbidden
	}
	return t, nil
}

// Update overwrites title and details; status is only changed when
// non-nil, so callers can update a task without having to know its
// current status.
func (s *TaskService) Update(ctx context.Context, userID, taskID uuid.UUID, title string, details *string, status *models.TaskStatus) (*models.Task, error) {
	t, err := s.Get(ctx, userID, taskID)
	if err != nil {
		return nil, err
	}
	t.Title = title
	t.Details = details
	if status != nil {
		t.Status = *status
	}
	if err := s.tasks.Update(ctx, t); err != nil {
		return nil, err
	}
	return t, nil
}

func (s *TaskService) Delete(ctx context.Context, userID, taskID uuid.UUID) error {
	// Confirm ownership first so a user can't delete another user's task by
	// guessing its ID.
	if _, err := s.Get(ctx, userID, taskID); err != nil {
		return err
	}
	return s.tasks.Delete(ctx, taskID)
}
