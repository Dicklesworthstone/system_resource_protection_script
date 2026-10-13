package sampler

import (
	"errors"
	"reflect"
	"testing"

	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
)

func okVM() (*mem.VirtualMemoryStat, error) {
	return &mem.VirtualMemoryStat{Total: 8 << 30, Used: 2 << 30}, nil
}
func okSwap() (*mem.SwapMemoryStat, error) { return &mem.SwapMemoryStat{Total: 0}, nil }
func okLoad() (*load.AvgStat, error)       { return &load.AvgStat{Load1: 1.5}, nil }

var errCollector = errors.New("collector failed")

func TestEssentialsAllAvailable(t *testing.T) {
	m, s, l, unavailable := essentials(okVM, okSwap, okLoad)
	if unavailable != nil {
		t.Fatalf("unavailable = %v, want none (swap Total 0 means no swap, not a failure)", unavailable)
	}
	if m.Total != 8<<30 || s.Total != 0 || l.Load1 != 1.5 {
		t.Fatalf("values not passed through: %+v %+v %+v", m, s, l)
	}
}

func TestEssentialsNeverDereferenceNil(t *testing.T) {
	vmNil := func() (*mem.VirtualMemoryStat, error) { return nil, errCollector }
	swNil := func() (*mem.SwapMemoryStat, error) { return nil, nil }
	laNil := func() (*load.AvgStat, error) { return nil, errCollector }

	m, s, l, unavailable := essentials(vmNil, swNil, laNil)
	if m == nil || s == nil || l == nil {
		t.Fatal("essentials returned a nil stat")
	}
	if want := []string{"memory", "swap", "load"}; !reflect.DeepEqual(unavailable, want) {
		t.Fatalf("unavailable = %v, want %v", unavailable, want)
	}
}

func TestEssentialsZeroMemoryTotalIsUnavailable(t *testing.T) {
	// gopsutil v3 returns a nonnil zero stat without an error when
	// /proc/meminfo cannot be read; that must not be published as 0 bytes.
	vmZero := func() (*mem.VirtualMemoryStat, error) { return &mem.VirtualMemoryStat{}, nil }
	_, _, _, unavailable := essentials(vmZero, okSwap, okLoad)
	if !reflect.DeepEqual(unavailable, []string{"memory"}) {
		t.Fatalf("unavailable = %v, want [memory]", unavailable)
	}
}

func TestEssentialsErrorWithValueIsUnavailable(t *testing.T) {
	vmErr := func() (*mem.VirtualMemoryStat, error) { return &mem.VirtualMemoryStat{Total: 1}, errCollector }
	_, _, _, unavailable := essentials(vmErr, okSwap, okLoad)
	if !reflect.DeepEqual(unavailable, []string{"memory"}) {
		t.Fatalf("unavailable = %v, want [memory]", unavailable)
	}
}
