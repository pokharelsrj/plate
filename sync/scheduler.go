package sync

import (
	"context"
	"log"
	"sync"
	"time"

	"pi-webpage/db"

	"github.com/robfig/cron/v3"
)

type Source struct {
	Name     string
	Backfill int
	Daily    int
	Run      func(ctx context.Context, days int) (int, error)
}

var Sources = []Source{
	{Name: "lafitness", Backfill: 60, Daily: 3, Run: SyncLAFitness},
	{Name: "healthifyme", Backfill: 60, Daily: 2, Run: SyncHealthifyme},
}

var (
	running   = map[string]bool{}
	runningMu sync.Mutex
)

func setRunning(name string, v bool) bool {
	runningMu.Lock()
	defer runningMu.Unlock()
	if v {
		if running[name] {
			return false
		}
		running[name] = true
		return true
	}
	delete(running, name)
	return true
}

func IsRunning(name string) bool {
	runningMu.Lock()
	defer runningMu.Unlock()
	return running[name]
}

func RunSource(ctx context.Context, src Source, days int) {
	if !setRunning(src.Name, true) {
		log.Printf("sync %s: already running, skipping", src.Name)
		return
	}
	defer setRunning(src.Name, false)

	id, err := db.StartSyncRun(src.Name)
	if err != nil {
		log.Printf("sync %s: start run: %v", src.Name, err)
		return
	}
	log.Printf("sync %s: starting (days=%d)", src.Name, days)
	n, runErr := src.Run(ctx, days)
	if err := db.FinishSyncRun(id, n, runErr); err != nil {
		log.Printf("sync %s: finish run: %v", src.Name, err)
	}
	if runErr != nil {
		log.Printf("sync %s: failed: %v", src.Name, runErr)
	} else {
		log.Printf("sync %s: done, %d records", src.Name, n)
	}
}

func srcByName(name string) (Source, bool) {
	for _, s := range Sources {
		if s.Name == name {
			return s, true
		}
	}
	return Source{}, false
}

func TriggerManual(name string, days int) bool {
	src, ok := srcByName(name)
	if !ok {
		return false
	}
	if days <= 0 {
		days = src.Daily
	}
	go RunSource(context.Background(), src, days)
	return true
}

func StartScheduler() {
	c := cron.New()
	// LA Fitness sync at 12:15 AM local
	_, _ = c.AddFunc("15 0 * * *", func() {
		RunSource(context.Background(), Sources[0], Sources[0].Daily)
	})
	// Healthifyme sync at 12:30 AM local
	_, _ = c.AddFunc("30 0 * * *", func() {
		RunSource(context.Background(), Sources[1], Sources[1].Daily)
	})
	c.Start()
	log.Println("cron scheduler started")
}

func MaybeInitialBackfill() {
	go func() {
		// LA Fitness: if no checkins, backfill
		if n, err := db.CheckinCount(); err == nil && n == 0 {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			RunSource(ctx, Sources[0], Sources[0].Backfill)
			cancel()
		}
		// Healthifyme: if no nutrition data, backfill
		if n, err := db.NutritionCount(); err == nil && n == 0 {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
			RunSource(ctx, Sources[1], Sources[1].Backfill)
			cancel()
		}
	}()
}
