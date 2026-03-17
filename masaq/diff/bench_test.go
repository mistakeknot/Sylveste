package diff_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/mistakeknot/Masaq/diff"
)

// generateFile creates a file with n lines of Go-like content.
func generateFile(n int) string {
	var sb strings.Builder
	for i := 0; i < n; i++ {
		fmt.Fprintf(&sb, "// line %d: func process_%d(ctx context.Context) error {\n", i, i)
	}
	return sb.String()
}

// mutateFile changes approximately pct% of lines in the content.
func mutateFile(content string, pct int) string {
	lines := strings.Split(content, "\n")
	step := 100 / pct
	if step < 1 {
		step = 1
	}
	for i := range lines {
		if i%step == 0 && lines[i] != "" {
			lines[i] = lines[i] + " // MODIFIED"
		}
	}
	return strings.Join(lines, "\n")
}

func BenchmarkLCS100Lines1Pct(b *testing.B) {
	before := generateFile(100)
	after := mutateFile(before, 1)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS100Lines5Pct(b *testing.B) {
	before := generateFile(100)
	after := mutateFile(before, 5)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS100Lines10Pct(b *testing.B) {
	before := generateFile(100)
	after := mutateFile(before, 10)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS500Lines5Pct(b *testing.B) {
	before := generateFile(500)
	after := mutateFile(before, 5)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS500Lines10Pct(b *testing.B) {
	before := generateFile(500)
	after := mutateFile(before, 10)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS2000Lines1Pct(b *testing.B) {
	before := generateFile(2000)
	after := mutateFile(before, 1)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS2000Lines5Pct(b *testing.B) {
	before := generateFile(2000)
	after := mutateFile(before, 5)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}

func BenchmarkLCS2000Lines10Pct(b *testing.B) {
	before := generateFile(2000)
	after := mutateFile(before, 10)
	d := diff.New(120)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		d.Render(before, after, "bench.go")
	}
}
