package main

import (
	"bytes"
	"context"
	"fmt"
	"math"
	"math/rand"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// ═══════════════════════════════════════════════════════
// 1. YAML 渲染正确性测试
// ═══════════════════════════════════════════════════════

func TestRenderBasicPod_GodelScheduler(t *testing.T) {
	var buf bytes.Buffer
	renderBasicPod(&buf, 42, "bench", "godel-scheduler", 100, 128, "registry.k8s.io/pause:3.9")
	yaml := buf.String()

	checks := []struct {
		name    string
		pattern string
	}{
		{"doc separator", `(?m)^---$`},
		{"apiVersion", `apiVersion: v1`},
		{"kind", `kind: Pod`},
		{"name", `name: bench-pod-42`},
		{"namespace", `namespace: bench`},
		{"godel pod-state", `godel.bytedance.com/pod-state: pending`},
		{"godel resource-type", `godel.bytedance.com/pod-resource-type: guaranteed`},
		{"godel launcher", `godel.bytedance.com/pod-launcher: kubelet`},
		{"schedulerName", `schedulerName: godel-scheduler`},
		{"terminationGrace", `terminationGracePeriodSeconds: 0`},
		{"image", `image: registry.k8s.io/pause:3.9`},
		{"cpu request", `cpu: "100m"`},
		{"mem request", `memory: "128Mi"`},
	}

	for _, c := range checks {
		t.Run(c.name, func(t *testing.T) {
			if !regexp.MustCompile(c.pattern).MatchString(yaml) {
				t.Errorf("pattern %q not found in YAML:\n%s", c.pattern, yaml)
			}
		})
	}
}

func TestRenderVolcanoPod(t *testing.T) {
	var buf bytes.Buffer
	renderVolcanoPod(&buf, 7, "bench", "volcano", 200, 256, "pause:3.9")
	yaml := buf.String()

	checks := []struct {
		name    string
		pattern string
	}{
		{"doc separator", `(?m)^---$`},
		{"name", `name: bench-pod-7`},
		{"volcano annotation", `scheduling.volcano.sh/group-name: bench-basic-pg`},
		{"schedulerName", `schedulerName: volcano`},
		{"cpu", `cpu: "200m"`},
		{"mem", `memory: "256Mi"`},
	}

	for _, c := range checks {
		t.Run(c.name, func(t *testing.T) {
			if !regexp.MustCompile(c.pattern).MatchString(yaml) {
				t.Errorf("pattern %q not found in YAML:\n%s", c.pattern, yaml)
			}
		})
	}

	// 不应包含 godel 注解
	if strings.Contains(yaml, "godel.bytedance.com") {
		t.Error("Volcano pod should not contain godel annotations")
	}
}

func TestRenderBasicPod_MultipleDocsHaveSeparators(t *testing.T) {
	var buf bytes.Buffer
	for i := 1; i <= 5; i++ {
		renderBasicPod(&buf, i, "test-ns", "default-scheduler", 50, 64, "pause:3.9")
	}

	yaml := buf.String()
	docs := strings.Split(yaml, "---\n")

	// 第一个 split 结果是 "---" 之前的空字符串
	// 每个 renderBasicPod 自带 --- 前缀，所以 5 个 Pod 产生 5 个 ---
	nonEmpty := 0
	for _, d := range docs {
		if strings.TrimSpace(d) != "" {
			nonEmpty++
		}
	}
	if nonEmpty != 5 {
		t.Errorf("expected 5 YAML documents, got %d. Full output:\n%s", nonEmpty, yaml)
	}

	// 验证 Pod 名称连续
	for i := 1; i <= 5; i++ {
		name := fmt.Sprintf("name: bench-pod-%d", i)
		if !strings.Contains(yaml, name) {
			t.Errorf("missing pod name: %s", name)
		}
	}
}

// ═══════════════════════════════════════════════════════
// 2. Gang YAML 渲染测试
// ═══════════════════════════════════════════════════════

func TestRenderGangGroup_Godel(t *testing.T) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	renderGangGroup(&buf, 3, 5, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	yaml := buf.String()

	// 应有 1 个 PodGroup + 5 个 Pod = 6 个 YAML 文档
	separators := strings.Count(yaml, "---\n")
	// PodGroup 以 ---\n 开头, 每个 Pod 以 ---\n 开头 = 6 个
	if separators < 6 {
		t.Errorf("expected >= 6 document separators, got %d", separators)
	}

	// PodGroup 验证
	if !strings.Contains(yaml, "kind: PodGroup") {
		t.Error("missing PodGroup")
	}
	if !strings.Contains(yaml, "name: bench-gang-3") {
		t.Error("wrong PodGroup name")
	}
	if !strings.Contains(yaml, "minMember: 5") {
		t.Error("wrong minMember")
	}
	if !strings.Contains(yaml, "scheduling.godel.kubewharf.io/v1alpha1") {
		t.Error("wrong PodGroup apiVersion for godel")
	}

	// 5 个 member Pod
	for m := 1; m <= 5; m++ {
		name := fmt.Sprintf("name: bench-gang-3-%d", m)
		if !strings.Contains(yaml, name) {
			t.Errorf("missing gang member: %s", name)
		}
	}

	// godel 特有注解
	if !strings.Contains(yaml, "scheduling.godel.bytedance.com/pod-group-name: bench-gang-3") {
		t.Error("missing godel pod-group-name annotation")
	}
}

func TestRenderGangGroup_Volcano(t *testing.T) {
	origScheduler := scheduler
	scheduler = "volcano"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	renderGangGroup(&buf, 1, 3, "bench", "volcano", 100, 128, "pause:3.9")
	yaml := buf.String()

	if !strings.Contains(yaml, "scheduling.volcano.sh/v1beta1") {
		t.Error("wrong PodGroup apiVersion for volcano")
	}
	if !strings.Contains(yaml, "scheduling.volcano.sh/group-name: bench-gang-1") {
		t.Error("missing volcano group-name annotation on member pod")
	}
	for m := 1; m <= 3; m++ {
		name := fmt.Sprintf("name: bench-gang-1-%d", m)
		if !strings.Contains(yaml, name) {
			t.Errorf("missing volcano gang member: %s", name)
		}
	}
}

func TestRenderGangGroup_Koordinator(t *testing.T) {
	origScheduler := scheduler
	scheduler = "koord-scheduler"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	renderGangGroup(&buf, 2, 4, "bench", "koord-scheduler", 200, 256, "pause:3.9")
	yaml := buf.String()

	if !strings.Contains(yaml, "scheduling.sigs.k8s.io/v1alpha1") {
		t.Error("wrong PodGroup apiVersion for koordinator")
	}
	if !strings.Contains(yaml, "scheduleTimeoutSeconds: 300") {
		t.Error("missing scheduleTimeoutSeconds for koordinator")
	}
	if !strings.Contains(yaml, "pod-group.scheduling.sigs.k8s.io: bench-gang-2") {
		t.Error("missing koordinator pod-group label on member pod")
	}
}

// ═══════════════════════════════════════════════════════
// 3. 令牌桶速率控制器测试
// ═══════════════════════════════════════════════════════

func TestRateLimiter_BasicAccuracy(t *testing.T) {
	// 测试速率: 1000 tokens/s，持续 2 秒，应得到约 2000 个 token
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	rl := newRateLimiter(1000)
	totalGot := 0

	for {
		got, err := rl.waitForSlot(ctx, 100)
		if err != nil {
			break
		}
		totalGot += got
	}

	// 允许 ±15% 误差（考虑 goroutine 调度延迟）
	expectedMin := 1700
	expectedMax := 2300
	if totalGot < expectedMin || totalGot > expectedMax {
		t.Errorf("rate 1000/s for 2s: expected %d~%d tokens, got %d", expectedMin, expectedMax, totalGot)
	}
}

func TestRateLimiter_LowRate(t *testing.T) {
	// 低速率: 10 tokens/s，持续 1 秒
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	rl := newRateLimiter(10)
	totalGot := 0

	for {
		got, err := rl.waitForSlot(ctx, 5)
		if err != nil {
			break
		}
		totalGot += got
	}

	// 10/s × 1s = 10, 允许 ±30%（短时间窗口误差较大）
	if totalGot < 7 || totalGot > 14 {
		t.Errorf("rate 10/s for 1s: expected 7~14 tokens, got %d", totalGot)
	}
}

func TestRateLimiter_HighRate(t *testing.T) {
	// 高速率: 5000 tokens/s，持续 1 秒
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	rl := newRateLimiter(5000)
	totalGot := 0

	for {
		got, err := rl.waitForSlot(ctx, 500)
		if err != nil {
			break
		}
		totalGot += got
	}

	// 5000/s × 1s = 5000, 允许 ±10%
	if totalGot < 4500 || totalGot > 5500 {
		t.Errorf("rate 5000/s for 1s: expected 4500~5500 tokens, got %d", totalGot)
	}
}

func TestRateLimiter_ChangeRate(t *testing.T) {
	// 先 500/s 持续 1 秒，再切到 1000/s 持续 1 秒
	ctx, cancel := context.WithTimeout(context.Background(), 2100*time.Millisecond)
	defer cancel()

	rl := newRateLimiter(500)
	totalGot := 0
	phase1End := time.Now().Add(1 * time.Second)

	// Phase 1: 500/s
	for time.Now().Before(phase1End) {
		got, err := rl.waitForSlot(ctx, 50)
		if err != nil {
			break
		}
		totalGot += got
	}
	phase1Got := totalGot

	// Phase 2: 1000/s
	rl.changeRate(1000)
	for {
		got, err := rl.waitForSlot(ctx, 100)
		if err != nil {
			break
		}
		totalGot += got
	}
	phase2Got := totalGot - phase1Got

	// Phase 1 应该约 500，Phase 2 约 1000（+追赶）
	if phase1Got < 350 || phase1Got > 700 {
		t.Errorf("phase1 (500/s × 1s): expected 350~700, got %d", phase1Got)
	}
	// phase2 可能更多（因为追赶机制）
	if phase2Got < 700 {
		t.Errorf("phase2 (1000/s × 1s): expected >= 700, got %d", phase2Got)
	}
}

func TestRateLimiter_CancelContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	rl := newRateLimiter(100)

	// 先消耗所有初始 budget
	rl.waitForSlot(ctx, 1)

	// 立刻取消
	cancel()
	_, err := rl.waitForSlot(ctx, 10)
	if err == nil {
		t.Error("expected error from cancelled context, got nil")
	}
}

// 测速率稳定性：在 3 秒内采样每秒实际获得的 token 数，
// 检查标准差 / 均值 (CV) < 阈值
func TestRateLimiter_Stability(t *testing.T) {
	targetRate := 2000
	duration := 3 * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), duration)
	defer cancel()

	rl := newRateLimiter(targetRate)

	// 每 100ms 采样一次
	type sample struct {
		ts    time.Time
		count int
	}
	samples := make([]sample, 0, 100)
	windowStart := time.Now()
	windowCount := 0

	for {
		got, err := rl.waitForSlot(ctx, 200)
		if err != nil {
			break
		}
		windowCount += got
		now := time.Now()
		if now.Sub(windowStart) >= 500*time.Millisecond {
			samples = append(samples, sample{ts: now, count: windowCount})
			windowStart = now
			windowCount = 0
		}
	}

	if len(samples) < 4 {
		t.Fatalf("not enough samples: %d", len(samples))
	}

	// 计算每 500ms 窗口的速率 (pods/s)
	rates := make([]float64, len(samples))
	for i, s := range samples {
		rates[i] = float64(s.count) * 2.0 // 500ms window → 乘2 得到 /s
	}

	mean, stddev := meanStddev(rates)
	cv := stddev / mean

	t.Logf("rate samples: %v", rates)
	t.Logf("mean=%.0f stddev=%.0f CV=%.3f", mean, stddev, cv)

	// CV < 0.30（30%）对于纯 CPU 令牌桶来说应该很宽松
	if cv > 0.30 {
		t.Errorf("rate stability too low: CV=%.3f > 0.30 (mean=%.0f, stddev=%.0f)", cv, mean, stddev)
	}
}

func meanStddev(data []float64) (float64, float64) {
	n := float64(len(data))
	sum := 0.0
	for _, v := range data {
		sum += v
	}
	mean := sum / n

	variance := 0.0
	for _, v := range data {
		d := v - mean
		variance += d * d
	}
	variance /= n
	return mean, math.Sqrt(variance)
}

// ═══════════════════════════════════════════════════════
// 4. 异构资源分布测试
// ═══════════════════════════════════════════════════════

func TestRandomHeteroSpec_Distribution(t *testing.T) {
	rng := rand.New(rand.NewSource(12345))
	n := 100000

	counts := map[int]int{} // cpu → count
	for i := 0; i < n; i++ {
		spec := randomHeteroSpec(rng)
		counts[spec.cpu]++
	}

	// 期望比例: 30% 小(50), 40% 中(200), 20% 大(1000), 10% 超大(4000)
	expectations := []struct {
		cpu      int
		expected float64
		label    string
	}{
		{50, 0.30, "小(50m)"},
		{200, 0.40, "中(200m)"},
		{1000, 0.20, "大(1000m)"},
		{4000, 0.10, "超大(4000m)"},
	}

	for _, e := range expectations {
		actual := float64(counts[e.cpu]) / float64(n)
		deviation := math.Abs(actual - e.expected)
		t.Logf("%s: expected %.2f, actual %.4f, deviation %.4f", e.label, e.expected, actual, deviation)
		// 允许 2% 绝对误差
		if deviation > 0.02 {
			t.Errorf("%s: deviation %.4f > 0.02 (expected %.2f, got %.4f)", e.label, deviation, e.expected, actual)
		}
	}
}

func TestRandomHeteroSpec_MemConsistency(t *testing.T) {
	rng := rand.New(rand.NewSource(99))
	// 验证 cpu/mem 配对一致
	expected := map[int]int{50: 64, 200: 256, 1000: 1024, 4000: 8192}

	for i := 0; i < 1000; i++ {
		spec := randomHeteroSpec(rng)
		if exp, ok := expected[spec.cpu]; ok {
			if spec.mem != exp {
				t.Fatalf("cpu=%d should pair with mem=%d, got mem=%d", spec.cpu, exp, spec.mem)
			}
		} else {
			t.Fatalf("unexpected cpu value: %d", spec.cpu)
		}
	}
}

// ═══════════════════════════════════════════════════════
// 5. parseStages 工具函数测试
// ═══════════════════════════════════════════════════════

func TestParseStages_Normal(t *testing.T) {
	stages := parseStages("200,500,1000,2000,1000,500,200")
	expected := []int{200, 500, 1000, 2000, 1000, 500, 200}

	if len(stages) != len(expected) {
		t.Fatalf("expected %d stages, got %d", len(expected), len(stages))
	}
	for i, v := range stages {
		if v != expected[i] {
			t.Errorf("stage[%d]: expected %d, got %d", i, expected[i], v)
		}
	}
}

func TestParseStages_WithSpaces(t *testing.T) {
	stages := parseStages(" 100 , 200 , 300 ")
	if len(stages) != 3 || stages[0] != 100 || stages[1] != 200 || stages[2] != 300 {
		t.Errorf("expected [100,200,300], got %v", stages)
	}
}

func TestParseStages_Empty(t *testing.T) {
	stages := parseStages("")
	if len(stages) == 0 {
		t.Error("empty input should return default stages")
	}
	// 应返回默认值
	if stages[0] != 200 {
		t.Errorf("default stages[0] should be 200, got %d", stages[0])
	}
}

func TestParseStages_InvalidValues(t *testing.T) {
	stages := parseStages("abc,0,-5,100")
	// 仅 100 是有效的 (>0)
	if len(stages) != 1 || stages[0] != 100 {
		t.Errorf("expected [100], got %v", stages)
	}
}

func TestParseStages_SingleValue(t *testing.T) {
	stages := parseStages("500")
	if len(stages) != 1 || stages[0] != 500 {
		t.Errorf("expected [500], got %v", stages)
	}
}

// ═══════════════════════════════════════════════════════
// 6. 端到端 Pipeline 测试（dry-run 模式）
// ═══════════════════════════════════════════════════════

// mockApplyWorker 模拟 apply，仅统计收到的 batch 数量和 Pod 数
func mockApplyWorker(ch <-chan yamlBatch, submitted *atomic.Int64, wg *sync.WaitGroup) {
	defer wg.Done()
	for batch := range ch {
		submitted.Add(int64(batch.size))
	}
}

func TestPipeline_BasicCompleteness(t *testing.T) {
	// 模拟 basic 模式: 500/s, 100 pods total, batch=50
	ch := make(chan yamlBatch, 16)
	var submitted atomic.Int64
	var wg sync.WaitGroup

	// 启动 mock workers
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go mockApplyWorker(ch, &submitted, &wg)
	}

	ctx := context.Background()
	render := renderBasicPod
	rl := newRateLimiter(5000) // 使用高速率使测试快速完成
	remaining := 100
	totalPods := 100
	batchSize := 50

	for remaining > 0 {
		want := batchSize
		if want > remaining {
			want = remaining
		}
		got, err := rl.waitForSlot(ctx, want)
		if err != nil {
			t.Fatal(err)
		}

		var buf bytes.Buffer
		for i := 0; i < got; i++ {
			podIdx := totalPods - remaining + i + 1
			render(&buf, podIdx, "bench", "godel-scheduler", 100, 128, "pause:3.9")
		}
		remaining -= got
		ch <- yamlBatch{data: buf.Bytes(), size: got}
	}

	close(ch)
	wg.Wait()

	if submitted.Load() != int64(totalPods) {
		t.Errorf("expected %d submitted pods, got %d", totalPods, submitted.Load())
	}
}

func TestPipeline_GangCompleteness(t *testing.T) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	ch := make(chan yamlBatch, 16)
	var submitted atomic.Int64
	var wg sync.WaitGroup

	for i := 0; i < 4; i++ {
		wg.Add(1)
		go mockApplyWorker(ch, &submitted, &wg)
	}

	ctx := context.Background()
	rl := newRateLimiter(10000)

	totalPods := 50
	gSize := 5
	totalGroups := totalPods / gSize
	groupBatch := 2
	remaining := totalGroups

	for remaining > 0 {
		want := groupBatch
		if want > remaining {
			want = remaining
		}
		got, err := rl.waitForSlot(ctx, want)
		if err != nil {
			t.Fatal(err)
		}

		var buf bytes.Buffer
		for g := 0; g < got; g++ {
			groupIdx := totalGroups - remaining + g + 1
			renderGangGroup(&buf, groupIdx, gSize, "bench", "godel-scheduler", 100, 128, "pause:3.9")
		}
		remaining -= got
		ch <- yamlBatch{data: buf.Bytes(), size: got * gSize}
	}

	close(ch)
	wg.Wait()

	if submitted.Load() != int64(totalPods) {
		t.Errorf("expected %d submitted pods, got %d", totalPods, submitted.Load())
	}
}

// ═══════════════════════════════════════════════════════
// 7. YAML 格式完整性测试
// ═══════════════════════════════════════════════════════

func TestYAML_ValidMultiDoc(t *testing.T) {
	// 生成 100 个 Pod 的 YAML，验证每个文档结构完整
	var buf bytes.Buffer
	for i := 1; i <= 100; i++ {
		renderBasicPod(&buf, i, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	}

	yaml := buf.String()

	// 每个文档都应以 "---" 开头并包含完整的 Pod 定义
	docs := splitYAMLDocs(yaml)
	if len(docs) != 100 {
		t.Fatalf("expected 100 documents, got %d", len(docs))
	}

	for i, doc := range docs {
		if !strings.Contains(doc, "apiVersion: v1") {
			t.Errorf("doc %d missing apiVersion", i+1)
		}
		if !strings.Contains(doc, "kind: Pod") {
			t.Errorf("doc %d missing kind", i+1)
		}
		expectedName := fmt.Sprintf("name: bench-pod-%d", i+1)
		if !strings.Contains(doc, expectedName) {
			t.Errorf("doc %d: expected %q, not found", i+1, expectedName)
		}
	}
}

func TestYAML_GangMultiDoc(t *testing.T) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	renderGangGroup(&buf, 1, 5, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	yaml := buf.String()

	docs := splitYAMLDocs(yaml)
	// 1 PodGroup + 5 Pods = 6 documents
	if len(docs) != 6 {
		t.Fatalf("expected 6 documents (1 PodGroup + 5 Pods), got %d.\nYAML:\n%s", len(docs), yaml)
	}

	// 第一个是 PodGroup
	if !strings.Contains(docs[0], "kind: PodGroup") {
		t.Error("first document should be PodGroup")
	}

	// 后 5 个是 Pod
	for i := 1; i <= 5; i++ {
		if !strings.Contains(docs[i], "kind: Pod") {
			t.Errorf("doc %d should be a Pod", i+1)
		}
	}
}

func TestYAML_NoDuplicateNames(t *testing.T) {
	var buf bytes.Buffer
	for i := 1; i <= 1000; i++ {
		renderBasicPod(&buf, i, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	}

	yaml := buf.String()
	nameRe := regexp.MustCompile(`name: bench-pod-(\d+)`)
	matches := nameRe.FindAllStringSubmatch(yaml, -1)

	seen := map[string]bool{}
	for _, m := range matches {
		if seen[m[1]] {
			t.Errorf("duplicate pod name: bench-pod-%s", m[1])
		}
		seen[m[1]] = true
	}

	if len(seen) != 1000 {
		t.Errorf("expected 1000 unique names, got %d", len(seen))
	}
}

// ═══════════════════════════════════════════════════════
// 8. 渲染性能基准测试
// ═══════════════════════════════════════════════════════

func BenchmarkRenderBasicPod(b *testing.B) {
	var buf bytes.Buffer
	buf.Grow(b.N * 350)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		buf.Reset()
		renderBasicPod(&buf, i, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	}
}

func BenchmarkRenderGangGroup(b *testing.B) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	buf.Grow(b.N * 2000)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		buf.Reset()
		renderGangGroup(&buf, i, 5, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	}
}

func BenchmarkRateLimiter_WaitForSlot(b *testing.B) {
	ctx := context.Background()
	rl := newRateLimiter(1000000) // 极高速率，不产生实际等待
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rl.waitForSlot(ctx, 1)
	}
}

func BenchmarkRender1000Pods(b *testing.B) {
	b.ResetTimer()
	for n := 0; n < b.N; n++ {
		var buf bytes.Buffer
		buf.Grow(1000 * 350)
		for i := 0; i < 1000; i++ {
			renderBasicPod(&buf, i, "bench", "godel-scheduler", 100, 128, "pause:3.9")
		}
	}
}

// ═══════════════════════════════════════════════════════
// 9. selectRenderer 测试
// ═══════════════════════════════════════════════════════

func TestSelectRenderer_Godel(t *testing.T) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	r := selectRenderer()
	var buf bytes.Buffer
	r(&buf, 1, "bench", "godel-scheduler", 100, 128, "pause:3.9")

	if !strings.Contains(buf.String(), "godel.bytedance.com/pod-state") {
		t.Error("godel renderer should include godel annotations")
	}
}

func TestSelectRenderer_Volcano(t *testing.T) {
	origScheduler := scheduler
	scheduler = "volcano"
	defer func() { scheduler = origScheduler }()

	r := selectRenderer()
	var buf bytes.Buffer
	r(&buf, 1, "bench", "volcano", 100, 128, "pause:3.9")

	if !strings.Contains(buf.String(), "scheduling.volcano.sh/group-name") {
		t.Error("volcano renderer should include volcano annotations")
	}
}

func TestSelectRenderer_DefaultScheduler(t *testing.T) {
	origScheduler := scheduler
	scheduler = "default-scheduler"
	defer func() { scheduler = origScheduler }()

	r := selectRenderer()
	var buf bytes.Buffer
	r(&buf, 1, "bench", "default-scheduler", 100, 128, "pause:3.9")

	// default-scheduler 使用 godel basic 模板（带 godel annotations）
	if !strings.Contains(buf.String(), "godel.bytedance.com/pod-state") {
		t.Error("default-scheduler should use basic renderer with godel annotations")
	}
}

// ═══════════════════════════════════════════════════════
// 10. 边界条件测试
// ═══════════════════════════════════════════════════════

func TestRenderBasicPod_LargeIndex(t *testing.T) {
	var buf bytes.Buffer
	renderBasicPod(&buf, 999999, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	if !strings.Contains(buf.String(), "name: bench-pod-999999") {
		t.Error("large index pod name not rendered correctly")
	}
}

func TestRenderBasicPod_LargeResources(t *testing.T) {
	var buf bytes.Buffer
	renderBasicPod(&buf, 1, "bench", "godel-scheduler", 4000, 8192, "pause:3.9")
	yaml := buf.String()

	if !strings.Contains(yaml, `cpu: "4000m"`) {
		t.Error("large CPU not rendered correctly")
	}
	if !strings.Contains(yaml, `memory: "8192Mi"`) {
		t.Error("large memory not rendered correctly")
	}
}

func TestRateLimiter_SingleToken(t *testing.T) {
	ctx := context.Background()
	rl := newRateLimiter(1)

	got, err := rl.waitForSlot(ctx, 1)
	if err != nil {
		t.Fatal(err)
	}
	if got != 1 {
		t.Errorf("expected 1 token, got %d", got)
	}
}

func TestRateLimiter_BatchLargerThanBudget(t *testing.T) {
	ctx := context.Background()
	rl := newRateLimiter(10)

	// 第一次调用时 budget 最多为 1（elapsed ≈ 0, allowed = 0*10+1 = 1）
	got, err := rl.waitForSlot(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	// 不应超过令牌桶的当前预算
	if got > 1000 {
		t.Errorf("got %d tokens, should not exceed requested 1000", got)
	}
	if got < 1 {
		t.Errorf("should get at least 1 token, got %d", got)
	}
}

func TestPipeline_ZeroTotal(t *testing.T) {
	// total=0 不应有任何输出
	ch := make(chan yamlBatch, 4)
	var submitted atomic.Int64
	var wg sync.WaitGroup

	wg.Add(1)
	go mockApplyWorker(ch, &submitted, &wg)

	remaining := 0
	// 循环不应执行
	for remaining > 0 {
		t.Fatal("should not enter loop with remaining=0")
	}

	close(ch)
	wg.Wait()

	if submitted.Load() != 0 {
		t.Errorf("expected 0 submitted, got %d", submitted.Load())
	}
}

func TestGangGroup_BatchSize1(t *testing.T) {
	origScheduler := scheduler
	scheduler = "godel-scheduler"
	defer func() { scheduler = origScheduler }()

	var buf bytes.Buffer
	renderGangGroup(&buf, 1, 1, "bench", "godel-scheduler", 100, 128, "pause:3.9")
	yaml := buf.String()

	docs := splitYAMLDocs(yaml)
	// 1 PodGroup + 1 Pod = 2 documents
	if len(docs) != 2 {
		t.Errorf("gang group with size 1: expected 2 docs, got %d", len(docs))
	}
}

// ═══════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════

// splitYAMLDocs 将多文档 YAML 按 "---" 分割，过滤空文档
func splitYAMLDocs(yaml string) []string {
	parts := strings.Split(yaml, "---\n")
	docs := make([]string, 0, len(parts))
	for _, p := range parts {
		if strings.TrimSpace(p) != "" {
			docs = append(docs, p)
		}
	}
	return docs
}
