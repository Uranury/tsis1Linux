// Package migrations embeds the SQL migration files into the compiled
// binary so deployment doesn't need to ship this directory alongside it.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
