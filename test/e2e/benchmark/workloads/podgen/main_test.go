package main

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	k8stesting "k8s.io/client-go/testing"
)

// ═══════════════════════════════════════════════════════════════════
// 1. Pod 构造测试
// ═══════════════════════════════════════════════════════════════════

func TestBuildBasicPod_EnoScheduler(t *testing.T) {
	flagScheduler = "eno-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	pod := buildBasicPod(42)

	if pod.Name != "bench-pod-42" {
		t.Errorf("name = %q, want bench-pod-42", pod.Name)
	}
	if pod.Namespace != "bench" {
		t.Errorf("namespace = %q, want bench", pod.Namespace)
	}
	if pod.Spec.SchedulerName != "eno-scheduler" {
		t.Errorf("schedulerName = %q, want eno-scheduler", pod.Spec.SchedulerName)
	}
	if *pod.Spec.TerminationGracePeriodSeconds != 0 {
		t.Errorf("terminationGracePeriodSeconds = %d, want 0", *pod.Spec.TerminationGracePeriodSeconds)
	}

	// 验证 Gödel 注解
	expectedAnnotations := map[string]string{
		"eno.io/pod-state":         "pending",
		"eno.io/pod-resource-type": "guaranteed",
		"eno.io/pod-launcher":      "kubelet",
	}
	for k, want := range expectedAnnotations {
		if got := pod.Annotations[k]; got != want {
			t.Errorf("annotation[%s] = %q, want %q", k, got, want)
		}
	}

	// 验证资源
	container := pod.Spec.Containers[0]
	if container.Name != "app" {
		t.Errorf("container name = %q, want app", container.Name)
	}
	if container.Image != "registry.k8s.io/pause:3.9" {
		t.Errorf("image = %q, want registry.k8s.io/pause:3.9", container.Image)
	}
	cpuReq := container.Resources.Requests.Cpu().String()
	if cpuReq != "100m" {
		t.Errorf("cpu request = %s, want 100m", cpuReq)
	}
	memReq := container.Resources.Requests.Memory().String()
	if memReq != "128Mi" {
		t.Errorf("mem request = %s, want 128Mi", memReq)
	}
}

func TestBuildBasicPod_Volcano(t *testing.T) {
	flagScheduler = "volcano"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 200
	flagMem = 256

	pod := buildBasicPod(1)

	if pod.Spec.SchedulerName != "volcano" {
		t.Errorf("schedulerName = %q, want volcano", pod.Spec.SchedulerName)
	}
	if got := pod.Annotations["scheduling.volcano.sh/group-name"]; got != "bench-basic-pg" {
		t.Errorf("volcano annotation = %q, want bench-basic-pg", got)
	}

	cpuReq := pod.Spec.Containers[0].Resources.Requests.Cpu().String()
	if cpuReq != "200m" {
		t.Errorf("cpu = %s, want 200m", cpuReq)
	}
}

func TestBuildBasicPod_DefaultScheduler(t *testing.T) {
	flagScheduler = "default-scheduler"
	flagNamespace = "test-ns"
	flagCPU = 50
	flagMem = 64

	pod := buildBasicPod(99)

	if pod.Spec.SchedulerName != "default-scheduler" {
		t.Errorf("schedulerName = %q, want default-scheduler", pod.Spec.SchedulerName)
	}
	// default-scheduler 不应有特殊注解
	if len(pod.Annotations) != 0 {
		t.Errorf("annotations should be empty for default-scheduler, got %v", pod.Annotations)
	}
}

func TestBuildBasicPod_KoordScheduler(t *testing.T) {
	flagScheduler = "koord-scheduler"
	flagNamespace = "bench"
	flagCPU = 100
	flagMem = 128

	pod := buildBasicPod(1)

	if pod.Spec.SchedulerName != "koord-scheduler" {
		t.Errorf("schedulerName = %q, want koord-scheduler", pod.Spec.SchedulerName)
	}
	// koord-scheduler basic 模式不应有特殊注解
	if len(pod.Annotations) != 0 {
		t.Errorf("annotations should be empty for koord-scheduler basic, got %v", pod.Annotations)
	}
}

func TestBuildHeteroPod(t *testing.T) {
	flagScheduler = "eno-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	pod := buildHeteroPod(7, 4000, 8192)

	if pod.Name != "bench-pod-7" {
		t.Errorf("name = %q, want bench-pod-7", pod.Name)
	}
	// 异构 Pod 应该使用传入的 CPU/MEM 而非全局 flagCPU/flagMem
	cpuReq := pod.Spec.Containers[0].Resources.Requests.Cpu().String()
	if cpuReq != "4" {
		t.Errorf("cpu = %s, want 4 (4000m)", cpuReq)
	}
	memReq := pod.Spec.Containers[0].Resources.Requests.Memory().String()
	if memReq != "8Gi" {
		t.Errorf("mem = %s, want 8Gi (8192Mi)", memReq)
	}
}

// ═══════════════════════════════════════════════════════════════════
// 2. Gang Pod 构造测试
// ═══════════════════════════════════════════════════════════════════

func TestBuildGangPod_Eno(t *testing.T) {
	flagScheduler = "eno-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	pod := buildGangPod(3, 2)

	if pod.Name != "bench-gang-3-2" {
		t.Errorf("name = %q, want bench-gang-3-2", pod.Name)
	}
	if got := pod.Annotations["scheduling.eno.io/pod-group-name"]; got != "bench-gang-3" {
		t.Errorf("pod-group-name = %q, want bench-gang-3", got)
	}
	if got := pod.Annotations["eno.io/pod-state"]; got != "pending" {
		t.Errorf("pod-state = %q, want pending", got)
	}
}

func TestBuildGangPod_Volcano(t *testing.T) {
	flagScheduler = "volcano"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	pod := buildGangPod(5, 1)

	if pod.Name != "bench-gang-5-1" {
		t.Errorf("name = %q, want bench-gang-5-1", pod.Name)
	}
	if got := pod.Annotations["scheduling.volcano.sh/group-name"]; got != "bench-gang-5" {
		t.Errorf("group-name = %q, want bench-gang-5", got)
	}
}

func TestBuildGangPod_Koord(t *testing.T) {
	flagScheduler = "koord-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	pod := buildGangPod(10, 3)

	if pod.Name != "bench-gang-10-3" {
		t.Errorf("name = %q, want bench-gang-10-3", pod.Name)
	}
	if got := pod.Labels["pod-group.scheduling.sigs.k8s.io"]; got != "bench-gang-10" {
		t.Errorf("label = %q, want bench-gang-10", got)
	}
	// Koord 不应有 annotations
	if len(pod.Annotations) != 0 {
		t.Errorf("koord gang pod should not have annotations, got %v", pod.Annotations)
	}
}

// ═══════════════════════════════════════════════════════════════════
// 3. makeResources 测试
// ═══════════════════════════════════════════════════════════════════

func TestMakeResources(t *testing.T) {
	tests := []struct {
		cpu, mem int
		wantCPU  string
		wantMem  string
	}{
		{100, 128, "100m", "128Mi"},
		{1000, 1024, "1", "1Gi"},
		{50, 64, "50m", "64Mi"},
		{4000, 8192, "4", "8Gi"},
	}
	for _, tt := range tests {
		res := makeResources(tt.cpu, tt.mem)
		gotCPU := res.Requests.Cpu().String()
		gotMem := res.Requests.Memory().String()
		if gotCPU != tt.wantCPU {
			t.Errorf("makeResources(%d, _).cpu = %s, want %s", tt.cpu, gotCPU, tt.wantCPU)
		}
		if gotMem != tt.wantMem {
			t.Errorf("makeResources(_, %d).mem = %s, want %s", tt.mem, gotMem, tt.wantMem)
		}
		// Limits 应等于 Requests
		limCPU := res.Limits.Cpu().String()
		limMem := res.Limits.Memory().String()
		if limCPU != gotCPU {
			t.Errorf("limits.cpu = %s != requests.cpu = %s", limCPU, gotCPU)
		}
		if limMem != gotMem {
			t.Errorf("limits.mem = %s != requests.mem = %s", limMem, gotMem)
		}
	}
}

// ═══════════════════════════════════════════════════════════════════
// 4. 异构资源分布测试
// ═══════════════════════════════════════════════════════════════════

func TestRandomHeteroSpec_Distribution(t *testing.T) {
	rng := rand.New(rand.NewSource(12345))
	counts := make(map[int]int)
	n := 100000

	for i := 0; i < n; i++ {
		spec := randomHeteroSpec(rng)
		counts[spec.cpu]++
	}

	expected := map[int]float64{
		50:   0.30,
		200:  0.40,
		1000: 0.20,
		4000: 0.10,
	}

	for cpu, wantPct := range expected {
		gotPct := float64(counts[cpu]) / float64(n)
		diff := math.Abs(gotPct - wantPct)
		if diff > 0.01 { // 1% 容差
			t.Errorf("cpu=%d: got %.3f, want %.3f (diff %.3f > 0.01)", cpu, gotPct, wantPct, diff)
		}
	}
}

func TestRandomHeteroSpec_AllSpecs(t *testing.T) {
	rng := rand.New(rand.NewSource(99))
	seen := make(map[int]bool)

	for i := 0; i < 1000; i++ {
		spec := randomHeteroSpec(rng)
		seen[spec.cpu] = true
	}

	for _, hs := range heteroSpecs {
		if !seen[hs.spec.cpu] {
			t.Errorf("cpu=%d 从未出现", hs.spec.cpu)
		}
	}
}

// ═══════════════════════════════════════════════════════════════════
// 5. parseStages 测试
// ═══════════════════════════════════════════════════════════════════

func TestParseStages(t *testing.T) {
	tests := []struct {
		input string
		want  []int
	}{
		{"200,500,1000", []int{200, 500, 1000}},
		{"100", []int{100}},
		{"  200 , 500 , 1000 ", []int{200, 500, 1000}},
		{"200,0,500", []int{200, 500}},                           // 0 被过滤
		{"", []int{200, 500, 1000, 2000, 1000, 500, 200}},        // 默认值
		{"abc,xyz", []int{200, 500, 1000, 2000, 1000, 500, 200}}, // 非法输入走默认
	}

	for _, tt := range tests {
		got := parseStages(tt.input)
		if len(got) != len(tt.want) {
			t.Errorf("parseStages(%q) len = %d, want %d", tt.input, len(got), len(tt.want))
			continue
		}
		for i, v := range got {
			if v != tt.want[i] {
				t.Errorf("parseStages(%q)[%d] = %d, want %d", tt.input, i, v, tt.want[i])
			}
		}
	}
}

// ═══════════════════════════════════════════════════════════════════
// 6. 速率控制器测试
// ═══════════════════════════════════════════════════════════════════

func TestRateLimiter_BasicRate(t *testing.T) {
	ctx := context.Background()
	rl := newRateLimiter(1000) // 1000/s

	start := time.Now()
	count := 0
	for i := 0; i < 500; i++ {
		if err := rl.waitForSlot(ctx); err != nil {
			t.Fatal(err)
		}
		count++
	}
	elapsed := time.Since(start)

	// 500 tokens @ 1000/s ≈ 0.5s (允许 0.3-0.8s 的波动)
	if elapsed < 300*time.Millisecond {
		t.Errorf("太快: %v (500 tokens @ 1000/s 应需 ~500ms)", elapsed)
	}
	if elapsed > 800*time.Millisecond {
		t.Errorf("太慢: %v (500 tokens @ 1000/s 应需 ~500ms)", elapsed)
	}
	if count != 500 {
		t.Errorf("count = %d, want 500", count)
	}
}

func TestRateLimiter_ContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	rl := newRateLimiter(1) // 极慢速率

	// 消耗初始 token
	_ = rl.waitForSlot(ctx)

	// 取消 context 后应立即返回
	cancel()
	err := rl.waitForSlot(ctx)
	if err == nil {
		t.Error("expected error after context cancel")
	}
}

func TestRateLimiter_ChangeRate(t *testing.T) {
	ctx := context.Background()
	rl := newRateLimiter(100) // 初始 100/s

	// 消耗一些 token
	for i := 0; i < 10; i++ {
		_ = rl.waitForSlot(ctx)
	}

	// 提高到 10000/s
	rl.changeRate(10000)

	start := time.Now()
	for i := 0; i < 100; i++ {
		if err := rl.waitForSlot(ctx); err != nil {
			t.Fatal(err)
		}
	}
	elapsed := time.Since(start)

	// 100 tokens @ 10000/s 应该非常快 (< 100ms)
	if elapsed > 200*time.Millisecond {
		t.Errorf("changeRate 后太慢: %v", elapsed)
	}
}

func TestRateLimiter_Concurrent(t *testing.T) {
	ctx := context.Background()
	rl := newRateLimiter(2000)

	var total atomic.Int64
	var wg sync.WaitGroup

	// 用 10 个 goroutine 并发请求
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				if err := rl.waitForSlot(ctx); err != nil {
					return
				}
				total.Add(1)
			}
		}()
	}
	wg.Wait()

	if got := total.Load(); got != 1000 {
		t.Errorf("concurrent total = %d, want 1000", got)
	}
}

func TestRateLimiter_Accuracy(t *testing.T) {
	// 测试在 1 秒内速率是否准确
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	targetRate := 500
	rl := newRateLimiter(targetRate)

	count := 0
	for {
		if err := rl.waitForSlot(ctx); err != nil {
			break
		}
		count++
	}

	// 允许 ±15% 误差 (425-575)
	lo := int(float64(targetRate) * 0.85)
	hi := int(float64(targetRate) * 1.15)
	if count < lo || count > hi {
		t.Errorf("1s 内获取 %d tokens, 目标 %d (允许 %d-%d)", count, targetRate, lo, hi)
	}
}

// ═══════════════════════════════════════════════════════════════════
// 7. Worker 池 + fake client 测试
// ═══════════════════════════════════════════════════════════════════

func TestCreateWorker_DryRun(t *testing.T) {
	origDryRun := flagDryRun
	defer func() { flagDryRun = origDryRun }()
	flagDryRun = true

	ctx := context.Background()
	ch := make(chan podTask, 10)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	client := fake.NewSimpleClientset()
	wg.Add(1)
	go createWorker(ctx, client, ch, &submitted, &errors, &wg)

	for i := 0; i < 10; i++ {
		ch <- podTask{pod: &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Name: fmt.Sprintf("pod-%d", i), Namespace: "bench"},
		}}
	}
	close(ch)
	wg.Wait()

	if got := submitted.Load(); got != 10 {
		t.Errorf("dry-run submitted = %d, want 10", got)
	}
	if got := errors.Load(); got != 0 {
		t.Errorf("dry-run errors = %d, want 0", got)
	}
}

func TestCreateWorker_FakeClient(t *testing.T) {
	origDryRun := flagDryRun
	defer func() { flagDryRun = origDryRun }()
	flagDryRun = false

	ctx := context.Background()
	client := fake.NewSimpleClientset()

	ch := make(chan podTask, 20)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	// 启动 2 个 workers
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go createWorker(ctx, client, ch, &submitted, &errors, &wg)
	}

	flagNamespace = "test-ns"
	flagScheduler = "eno-scheduler"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128

	for i := 0; i < 20; i++ {
		ch <- podTask{pod: buildBasicPod(i + 1)}
	}
	close(ch)
	wg.Wait()

	if got := submitted.Load(); got != 20 {
		t.Errorf("submitted = %d, want 20", got)
	}
	if got := errors.Load(); got != 0 {
		t.Errorf("errors = %d, want 0", got)
	}

	// 验证 fake client 实际创建了 Pod
	pods, err := client.CoreV1().Pods("test-ns").List(ctx, metav1.ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(pods.Items) != 20 {
		t.Errorf("created pods = %d, want 20", len(pods.Items))
	}
}

func TestCreateWorker_WithErrors(t *testing.T) {
	origDryRun := flagDryRun
	defer func() { flagDryRun = origDryRun }()
	flagDryRun = false

	ctx := context.Background()
	client := fake.NewSimpleClientset()

	// 让前 5 次创建全部失败（包括重试）
	callCount := atomic.Int64{}
	client.PrependReactor("create", "pods", func(action k8stesting.Action) (bool, runtime.Object, error) {
		n := callCount.Add(1)
		// 前 15 次调用失败 (5 个 pod × 3 次重试 = 15 次调用)
		if n <= 15 {
			return true, nil, fmt.Errorf("simulated API error")
		}
		return false, nil, nil // 交给默认 handler
	})

	ch := make(chan podTask, 20)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	wg.Add(1)
	go createWorker(ctx, client, ch, &submitted, &errors, &wg)

	flagNamespace = "err-ns"
	flagScheduler = "default-scheduler"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128

	for i := 0; i < 10; i++ {
		ch <- podTask{pod: buildBasicPod(i + 1)}
	}
	close(ch)
	wg.Wait()

	if got := errors.Load(); got != 5 {
		t.Errorf("errors = %d, want 5", got)
	}
	if got := submitted.Load(); got != 5 {
		t.Errorf("submitted = %d, want 5", got)
	}
}

func TestCreateWorker_ContextCancel(t *testing.T) {
	origDryRun := flagDryRun
	defer func() { flagDryRun = origDryRun }()
	flagDryRun = false

	ctx, cancel := context.WithCancel(context.Background())
	client := fake.NewSimpleClientset()

	ch := make(chan podTask, 100)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup

	wg.Add(1)
	go createWorker(ctx, client, ch, &submitted, &errors, &wg)

	flagNamespace = "cancel-ns"
	flagScheduler = "default-scheduler"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128

	// 发送几个然后取消
	for i := 0; i < 5; i++ {
		ch <- podTask{pod: buildBasicPod(i + 1)}
	}
	time.Sleep(50 * time.Millisecond)
	cancel()
	close(ch)
	wg.Wait()

	// Worker 应该在 cancel 后停止
	// 不检查精确数量，只要不 panic 不死锁即可
	t.Logf("submitted=%d, errors=%d after cancel", submitted.Load(), errors.Load())
}

// ═══════════════════════════════════════════════════════════════════
// 8. 端到端 Pipeline 测试 (runBasic with fake client)
// ═══════════════════════════════════════════════════════════════════

func TestRunBasic_FakeClient(t *testing.T) {
	origRate := flagRate
	origTotal := flagTotal
	origWorkers := flagWorkers
	origScheduler := flagScheduler
	origNamespace := flagNamespace
	origImage := flagImage
	origCPU := flagCPU
	origMem := flagMem
	origDryRun := flagDryRun
	defer func() {
		flagRate = origRate
		flagTotal = origTotal
		flagWorkers = origWorkers
		flagScheduler = origScheduler
		flagNamespace = origNamespace
		flagImage = origImage
		flagCPU = origCPU
		flagMem = origMem
		flagDryRun = origDryRun
	}()

	flagRate = 10000 // 尽可能快
	flagTotal = 100
	flagWorkers = 4
	flagScheduler = "eno-scheduler"
	flagNamespace = "pipeline-ns"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128
	flagDryRun = false

	client := fake.NewSimpleClientset()
	ctx := context.Background()

	runBasic(ctx, client)

	pods, err := client.CoreV1().Pods("pipeline-ns").List(ctx, metav1.ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(pods.Items) != 100 {
		t.Errorf("created pods = %d, want 100", len(pods.Items))
	}
}

func TestRunGang_FakeClient(t *testing.T) {
	origRate := flagRate
	origTotal := flagTotal
	origWorkers := flagWorkers
	origScheduler := flagScheduler
	origNamespace := flagNamespace
	origImage := flagImage
	origCPU := flagCPU
	origMem := flagMem
	origGangSize := flagGangSize
	origDryRun := flagDryRun
	defer func() {
		flagRate = origRate
		flagTotal = origTotal
		flagWorkers = origWorkers
		flagScheduler = origScheduler
		flagNamespace = origNamespace
		flagImage = origImage
		flagCPU = origCPU
		flagMem = origMem
		flagGangSize = origGangSize
		flagDryRun = origDryRun
	}()

	flagRate = 10000
	flagTotal = 50 // 50 pods = 10 groups × 5
	flagWorkers = 4
	flagScheduler = "eno-scheduler"
	flagNamespace = "gang-ns"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128
	flagGangSize = 5
	flagDryRun = false

	client := fake.NewSimpleClientset()
	ctx := context.Background()

	// Gödel 不需要 PodGroup CRD，dynamic client 传 nil
	runGang(ctx, client, nil)

	pods, err := client.CoreV1().Pods("gang-ns").List(ctx, metav1.ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(pods.Items) != 50 {
		t.Errorf("gang pods = %d, want 50", len(pods.Items))
	}

	// 验证有 10 个不同的 group
	groups := make(map[string]int)
	for _, p := range pods.Items {
		pgName := p.Annotations["scheduling.eno.io/pod-group-name"]
		groups[pgName]++
	}
	if len(groups) != 10 {
		t.Errorf("unique groups = %d, want 10", len(groups))
	}
	for pg, count := range groups {
		if count != 5 {
			t.Errorf("group %s has %d members, want 5", pg, count)
		}
	}
}

func TestRunHeterogeneous_FakeClient(t *testing.T) {
	origRate := flagRate
	origTotal := flagTotal
	origWorkers := flagWorkers
	origScheduler := flagScheduler
	origNamespace := flagNamespace
	origImage := flagImage
	origCPU := flagCPU
	origMem := flagMem
	origDryRun := flagDryRun
	defer func() {
		flagRate = origRate
		flagTotal = origTotal
		flagWorkers = origWorkers
		flagScheduler = origScheduler
		flagNamespace = origNamespace
		flagImage = origImage
		flagCPU = origCPU
		flagMem = origMem
		flagDryRun = origDryRun
	}()

	flagRate = 10000
	flagTotal = 200
	flagWorkers = 4
	flagScheduler = "eno-scheduler"
	flagNamespace = "hetero-ns"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128
	flagDryRun = false

	client := fake.NewSimpleClientset()
	ctx := context.Background()

	runHeterogeneous(ctx, client)

	pods, err := client.CoreV1().Pods("hetero-ns").List(ctx, metav1.ListOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(pods.Items) != 200 {
		t.Errorf("hetero pods = %d, want 200", len(pods.Items))
	}

	// 验证有多种不同的 CPU 规格
	cpuSet := make(map[string]bool)
	for _, p := range pods.Items {
		cpu := p.Spec.Containers[0].Resources.Requests.Cpu().String()
		cpuSet[cpu] = true
	}
	if len(cpuSet) < 3 {
		t.Errorf("只出现 %d 种 CPU 规格, 期望至少 3 种 (异构)", len(cpuSet))
	}
}

// ═══════════════════════════════════════════════════════════════════
// 9. addSchedulerAnnotations 测试
// ═══════════════════════════════════════════════════════════════════

func TestAddSchedulerAnnotations(t *testing.T) {
	tests := []struct {
		scheduler       string
		wantAnnotations map[string]string
	}{
		{
			"eno-scheduler",
			map[string]string{
				"eno.io/pod-state":         "pending",
				"eno.io/pod-resource-type": "guaranteed",
				"eno.io/pod-launcher":      "kubelet",
			},
		},
		{
			"volcano",
			map[string]string{
				"scheduling.volcano.sh/group-name": "bench-basic-pg",
			},
		},
		{
			"default-scheduler",
			nil,
		},
		{
			"koord-scheduler",
			nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.scheduler, func(t *testing.T) {
			flagScheduler = tt.scheduler
			pod := &corev1.Pod{}
			addSchedulerAnnotations(pod)

			if tt.wantAnnotations == nil {
				if len(pod.Annotations) != 0 {
					t.Errorf("want no annotations, got %v", pod.Annotations)
				}
				return
			}
			for k, want := range tt.wantAnnotations {
				if got := pod.Annotations[k]; got != want {
					t.Errorf("annotation[%s] = %q, want %q", k, got, want)
				}
			}
		})
	}
}

// ═══════════════════════════════════════════════════════════════════
// 10. int64Ptr 测试
// ═══════════════════════════════════════════════════════════════════

func TestInt64Ptr(t *testing.T) {
	p := int64Ptr(42)
	if *p != 42 {
		t.Errorf("*int64Ptr(42) = %d, want 42", *p)
	}
	p2 := int64Ptr(0)
	if *p2 != 0 {
		t.Errorf("*int64Ptr(0) = %d, want 0", *p2)
	}
}

// ═══════════════════════════════════════════════════════════════════
// 11. ensureNamespace 测试
// ═══════════════════════════════════════════════════════════════════

func TestEnsureNamespace(t *testing.T) {
	flagNamespace = "test-ensure-ns"
	client := fake.NewSimpleClientset()
	ctx := context.Background()

	// 首次创建
	ensureNamespace(ctx, client)
	ns, err := client.CoreV1().Namespaces().Get(ctx, "test-ensure-ns", metav1.GetOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if ns.Name != "test-ensure-ns" {
		t.Errorf("ns name = %q, want test-ensure-ns", ns.Name)
	}

	// 重复调用不应 panic
	ensureNamespace(ctx, client)
}

// ═══════════════════════════════════════════════════════════════════
// Benchmarks
// ═══════════════════════════════════════════════════════════════════

func BenchmarkBuildBasicPod(b *testing.B) {
	flagScheduler = "eno-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		buildBasicPod(i)
	}
}

func BenchmarkBuildGangPod(b *testing.B) {
	flagScheduler = "eno-scheduler"
	flagNamespace = "bench"
	flagImage = "registry.k8s.io/pause:3.9"
	flagCPU = 100
	flagMem = 128

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		buildGangPod(i, 1)
	}
}

func BenchmarkMakeResources(b *testing.B) {
	for i := 0; i < b.N; i++ {
		makeResources(100, 128)
	}
}

func BenchmarkRandomHeteroSpec(b *testing.B) {
	rng := rand.New(rand.NewSource(42))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		randomHeteroSpec(rng)
	}
}

func BenchmarkRateLimiter_WaitForSlot(b *testing.B) {
	ctx := context.Background()
	rl := newRateLimiter(1000000) // 极高速率，测试函数开销
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = rl.waitForSlot(ctx)
	}
}

func BenchmarkCreateWorker_DryRun(b *testing.B) {
	origDryRun := flagDryRun
	defer func() { flagDryRun = origDryRun }()
	flagDryRun = true

	ctx := context.Background()
	ch := make(chan podTask, 1000)
	var submitted, errors atomic.Int64
	var wg sync.WaitGroup
	client := fake.NewSimpleClientset()

	wg.Add(1)
	go createWorker(ctx, client, ch, &submitted, &errors, &wg)

	flagNamespace = "bench"
	flagScheduler = "eno-scheduler"
	flagImage = "pause:latest"
	flagCPU = 100
	flagMem = 128

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ch <- podTask{pod: buildBasicPod(i)}
	}
	close(ch)
	wg.Wait()
}
