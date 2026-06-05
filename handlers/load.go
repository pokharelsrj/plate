package handlers

import "github.com/shirou/gopsutil/v3/load"

func getLoad() ([3]float64, error) {
	avg, err := load.Avg()
	if err != nil {
		return [3]float64{}, err
	}
	return [3]float64{avg.Load1, avg.Load5, avg.Load15}, nil
}
