package models

import (
	"time"

	"github.com/google/uuid"
)

type TaskStatus int

// Pending is the zero value so a freshly constructed Task defaults to
// "not done yet" rather than "completed".
const (
	Pending TaskStatus = iota
	Completed
	Skipped
)

func (s TaskStatus) String() string {
	switch s {
	case Pending:
		return "pending"
	case Completed:
		return "completed"
	case Skipped:
		return "skipped"
	default:
		return "unknown"
	}
}

type Task struct {
	ID      uuid.UUID  `json:"id" db:"id"`
	UserID  uuid.UUID  `json:"user_id" db:"user_id"`
	Title   string     `json:"title" db:"title"`
	Details *string    `json:"details,omitempty" db:"details"`
	Status  TaskStatus `json:"status" db:"status"`

	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}
