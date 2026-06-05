package handlers

import (
	"net/http"
	"time"

	"pi-webpage/components"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
)

func collectStats() (components.StatsData, error) {
	var s components.StatsData

	cpuPcts, err := cpu.Percent(500*time.Millisecond, false)
	if err == nil && len(cpuPcts) > 0 {
		s.CPUPercent = cpuPcts[0]
	}

	if vm, err := mem.VirtualMemory(); err == nil {
		s.MemPercent = vm.UsedPercent
		s.MemUsedGB = float64(vm.Used) / 1e9
		s.MemTotalGB = float64(vm.Total) / 1e9
	}

	if du, err := disk.Usage("/"); err == nil {
		s.DiskPercent = du.UsedPercent
		s.DiskUsedGB = float64(du.Used) / 1e9
		s.DiskTotalGB = float64(du.Total) / 1e9
	}

	if info, err := host.Info(); err == nil {
		s.UptimeHours = float64(info.Uptime) / 3600
	}

	if temps, err := host.SensorsTemperatures(); err == nil {
		for _, t := range temps {
			if t.Temperature > 0 && t.Temperature < 150 {
				s.TempCelsius = t.Temperature
				break
			}
		}
	}

	loadStat, err := getLoad()
	if err == nil {
		s.LoadAvg1 = loadStat[0]
		s.LoadAvg5 = loadStat[1]
		s.LoadAvg15 = loadStat[2]
	}

	return s, nil
}

func StatsPage(w http.ResponseWriter, r *http.Request) {
	s, _ := collectStats()
	components.StatsPage(s, time.Now()).Render(r.Context(), w)
}

func StatsData(w http.ResponseWriter, r *http.Request) {
	s, _ := collectStats()
	components.StatsPartial(s).Render(r.Context(), w)
}
