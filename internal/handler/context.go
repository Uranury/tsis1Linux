package handler

import (
	"context"

	"github.com/google/uuid"
)

type ctxKey int

const userIDKey ctxKey = iota

func userIDFromContext(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(userIDKey).(uuid.UUID)
	return id, ok
}
