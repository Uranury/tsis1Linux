package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/Uranury/tsis1Linux/internal/models"
	"github.com/Uranury/tsis1Linux/internal/repo"
	"github.com/Uranury/tsis1Linux/internal/service"
	"github.com/google/uuid"
)

type TaskHandler struct {
	tasks *service.TaskService
}

func NewTaskHandler(s *service.TaskService) *TaskHandler {
	return &TaskHandler{tasks: s}
}

type taskRequest struct {
	Title   string             `json:"title"`
	Details *string            `json:"details,omitempty"`
	Status  *models.TaskStatus `json:"status,omitempty"`
}

func (h *TaskHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req taskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Title == "" {
		writeError(w, http.StatusBadRequest, "title is required")
		return
	}

	t, err := h.tasks.Create(r.Context(), userID, req.Title, req.Details)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not create task")
		return
	}
	writeJSON(w, http.StatusCreated, t)
}

func (h *TaskHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	tasks, err := h.tasks.List(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "could not list tasks")
		return
	}
	if tasks == nil {
		tasks = []models.Task{} // so the response is `[]`, not `null`
	}
	writeJSON(w, http.StatusOK, tasks)
}

func (h *TaskHandler) Get(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid task id")
		return
	}

	t, err := h.tasks.Get(r.Context(), userID, id)
	if err != nil {
		writeTaskLookupError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (h *TaskHandler) Update(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid task id")
		return
	}

	var req taskRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Title == "" {
		writeError(w, http.StatusBadRequest, "title is required")
		return
	}

	t, err := h.tasks.Update(r.Context(), userID, id, req.Title, req.Details, req.Status)
	if err != nil {
		writeTaskLookupError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (h *TaskHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := userIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid task id")
		return
	}

	if err := h.tasks.Delete(r.Context(), userID, id); err != nil {
		writeTaskLookupError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// writeTaskLookupError maps a missing or not-owned task to 404 either way,
// so a client can't use the response to probe which task IDs exist.
func writeTaskLookupError(w http.ResponseWriter, err error) {
	if errors.Is(err, repo.ErrNotFound) || errors.Is(err, service.ErrForbidden) {
		writeError(w, http.StatusNotFound, "task not found")
		return
	}
	writeError(w, http.StatusInternalServerError, "could not process task")
}
