import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class WorkoutViewModel {
    var session: Session?

    var date: String = PiDate.todayString
    var exercises: [Exercise] = []
    var groups: [WorkoutGroup] = []
    var totalSets = 0
    var active: WorkoutActive?
    var todaySets: [WorkoutSet] = []

    var reps: Double = 10
    var weight: Double = 0

    var searchText = ""
    var toast: Toast?
    var errorMessage: String?
    var isLoaded = false

    /// Rest stopwatch — starts/restarts when a set is logged (today only).
    /// State is persisted via RestTimerStore so the lock-screen Live Activity
    /// intents and the app stay in sync.
    var restStartedAt: Date?
    private var stoppedRestStartedAt: Date?
    /// True when "Set done" was tapped before logging the set — the rest clock
    /// is already running from the real end of the set, so the subsequent
    /// ADD SET must not reset it. Persisted: the lock-screen reset sets it too.
    private var manualRestMark: Bool {
        get { UserDefaults.standard.bool(forKey: RestTimerStore.manualMarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: RestTimerStore.manualMarkKey) }
    }

    /// Sets removed locally and waiting out the 5s undo window before the server DELETE.
    private var pendingDeletes: [Int64: Task<Void, Never>] = [:]
    private var lastDeleted: (set: WorkoutSet, index: Int)?
    /// Temporary negative id for optimistic inserts.
    private var nextTempID: Int64 = -1

    private var client: APIClient? { session?.client }

    var activeExerciseKey: String { "workout.activeExercise" }

    /// Stored so @Observable picks up changes immediately; persisted per exercise.
    var weightStep: Double = 5 {
        didSet {
            guard let id = active?.exerciseId else { return }
            UserDefaults.standard.set(weightStep, forKey: "weightStep.\(id)")
        }
    }

    private func storedWeightStep(for exerciseId: Int64?) -> Double {
        guard let exerciseId else { return 5 }
        let v = UserDefaults.standard.double(forKey: "weightStep.\(exerciseId)")
        return v > 0 ? v : 5
    }

    var filteredPickerGroups: [(bodyPart: String, exercises: [Exercise])] {
        let filtered = searchText.isEmpty
            ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        var buckets: [String: [Exercise]] = [:]
        for e in filtered {
            buckets[e.bodyPart ?? "other", default: []].append(e)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0]!) }
    }

    // MARK: - Watch sync

    private var watchObserver: NSObjectProtocol?

    func startObservingWatch() {
        guard watchObserver == nil else { return }
        watchObserver = NotificationCenter.default.addObserver(
            forName: .watchDidAddSet, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let noteDate = note.userInfo?["date"] as? String ?? PiDate.todayString
            guard noteDate == self.date else { return }
            Task { await self.refresh(prefill: false) }
        }
    }

    // MARK: - Loading

    func load() async {
        guard let client else { return }
        do {
            let savedActive = UserDefaults.standard.object(forKey: activeExerciseKey) as? Int64
                ?? Int64(UserDefaults.standard.integer(forKey: activeExerciseKey))
            async let exercisesResp = client.exercises()
            let resp = try await client.workout(date: date, exerciseId: savedActive > 0 ? savedActive : nil)
            exercises = try await exercisesResp.exercises
            apply(resp, prefill: !isLoaded)
            isLoaded = true
            errorMessage = nil
        } catch APIError.notFound {
            // saved active exercise was deleted
            UserDefaults.standard.removeObject(forKey: activeExerciseKey)
            await refresh(prefill: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(prefill: Bool = false) async {
        guard let client else { return }
        do {
            let resp = try await client.workout(date: date, exerciseId: active?.exerciseId)
            apply(resp, prefill: prefill)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ resp: WorkoutResponse, prefill: Bool) {
        groups = resp.groups
        totalSets = resp.totalSets
        active = resp.active
        todaySets = resp.active?.todaySets ?? []
        // Hide rows that are mid-undo-window so a refresh doesn't resurrect them.
        if !pendingDeletes.isEmpty {
            todaySets.removeAll { pendingDeletes[$0.id] != nil }
        }
        if prefill, let a = resp.active {
            reps = Double(a.prefillReps)
            weight = a.prefillWeightLbs ?? 0
        }
        weightStep = storedWeightStep(for: resp.active?.exerciseId)
    }

    func selectExercise(_ exercise: Exercise) async {
        guard let client else { return }
        UserDefaults.standard.set(exercise.id, forKey: activeExerciseKey)
        do {
            let resp = try await client.workout(date: date, exerciseId: exercise.id)
            apply(resp, prefill: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// True while the screen should track the real calendar day. Cleared when
    /// the user browses to another date, restored when they return to today.
    private var followsToday = true

    /// Deselect the active exercise — done on every date change so the panel
    /// always starts fresh for the day being viewed.
    private func clearActive() {
        active = nil
        todaySets = []
        UserDefaults.standard.removeObject(forKey: activeExerciseKey)
        clearRestTimer()
    }

    // MARK: - Rest timer

    /// Reconcile in-memory state with the persisted store — picks up timers
    /// after a relaunch AND any reset/complete done from the lock screen
    /// while the app was backgrounded. Called on appear and on foreground.
    func restoreRestTimer() {
        guard date == PiDate.todayString else { return }
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: RestTimerStore.startKey) as? Date

        if let t = stored, Date().timeIntervalSince(t) < 30 * 60 {
            if restStartedAt != t {
                restStartedAt = t
                stoppedRestStartedAt = nil
                RestActivity.start(startedAt: t, exerciseName: active?.exerciseName ?? "Workout")
            }
        } else if stored == nil, restStartedAt != nil {
            // Completed from the lock screen — hide locally, keep resume option.
            stoppedRestStartedAt = defaults.object(forKey: RestTimerStore.stoppedKey) as? Date ?? restStartedAt
            restStartedAt = nil
        }
    }

    private func startRestTimer() {
        guard date == PiDate.todayString else { return }
        // "Set done" was tapped when the set physically ended — the clock is
        // already correct; don't reset it on the data entry that follows.
        if manualRestMark {
            manualRestMark = false
            return
        }
        setRestStart(Date())
    }

    /// "Set done" / reset — the set just physically ended; rest starts now.
    /// Works before the set details are entered.
    func markSetDone() {
        guard date == PiDate.todayString else { return }
        setRestStart(Date())
        manualRestMark = true
    }

    private func setRestStart(_ t: Date) {
        restStartedAt = t
        stoppedRestStartedAt = nil
        UserDefaults.standard.set(t, forKey: RestTimerStore.startKey)
        UserDefaults.standard.removeObject(forKey: RestTimerStore.stoppedKey)
        RestActivity.start(startedAt: t, exerciseName: active?.exerciseName ?? "Workout")
    }

    /// "Complete exercise" — hides the timer but remembers it for accidental taps.
    func completeExercise() {
        stoppedRestStartedAt = restStartedAt
        if let t = restStartedAt {
            UserDefaults.standard.set(t, forKey: RestTimerStore.stoppedKey)
        }
        restStartedAt = nil
        manualRestMark = false
        UserDefaults.standard.removeObject(forKey: RestTimerStore.startKey)
        RestActivity.end()
    }

    /// Undo an accidental complete — the timer resumes from the actual last set.
    func resumeRestTimer() {
        let stopped = stoppedRestStartedAt
            ?? UserDefaults.standard.object(forKey: RestTimerStore.stoppedKey) as? Date
        setRestStart(stopped ?? Date())
    }

    var canResumeRest: Bool { stoppedRestStartedAt != nil }

    private func clearRestTimer() {
        restStartedAt = nil
        stoppedRestStartedAt = nil
        manualRestMark = false
        UserDefaults.standard.removeObject(forKey: RestTimerStore.startKey)
        UserDefaults.standard.removeObject(forKey: RestTimerStore.stoppedKey)
        RestActivity.end()
    }

    func changeDate(by days: Int) async {
        guard let d = PiDate.parseDay(date) else { return }
        date = PiDate.dayString(Calendar.current.date(byAdding: .day, value: days, to: d) ?? d)
        followsToday = date == PiDate.todayString
        clearActive()
        await refresh(prefill: false)
    }

    func goToToday() async {
        date = PiDate.todayString
        followsToday = true
        clearActive()
        await refresh(prefill: false)
    }

    /// The view model survives overnight app suspensions; without this, a set
    /// logged the next morning would land on yesterday's date.
    func snapToTodayIfNeeded() async {
        guard followsToday, date != PiDate.todayString else { return }
        date = PiDate.todayString
        clearActive()
        await refresh(prefill: false)
    }

    // MARK: - Set mutations

    func addSet(reps repsIn: Int? = nil, weight weightIn: Double?? = nil) {
        guard let active else { return }
        let r = repsIn ?? Int(reps)
        let w: Double? = weightIn ?? (weight > 0 ? weight : nil)
        guard r > 0 else { return }

        let temp = WorkoutSet(id: nextTempID, date: date, exerciseId: active.exerciseId, reps: r, weightLbs: w)
        nextTempID -= 1
        withAnimation(.snappy) { todaySets.append(temp) }
        startRestTimer()

        Task {
            do {
                guard let client else { return }
                let saved = try await client.addSet(date: date, exerciseId: active.exerciseId, reps: r, weightLbs: w)
                if let idx = todaySets.firstIndex(where: { $0.id == temp.id }) {
                    todaySets[idx] = saved
                }
                await refresh(prefill: false)
            } catch {
                withAnimation { todaySets.removeAll { $0.id == temp.id } }
                toast = Toast(message: "Couldn't save set — \(error.localizedDescription)", isError: true)
            }
        }
    }

    /// Clone the most recent set (today's last, else last session's last).
    func repeatLast() {
        if let last = todaySets.last {
            addSet(reps: last.reps, weight: last.weightLbs)
        } else if let last = active?.lastSessionSets.last {
            addSet(reps: last.reps, weight: last.weightLbs)
        }
    }

    var canRepeatLast: Bool {
        !(todaySets.isEmpty && (active?.lastSessionSets.isEmpty ?? true))
    }

    func duplicate(_ set: WorkoutSet) {
        addSet(reps: set.reps, weight: set.weightLbs)
    }

    func cloneFromLastSession(_ set: WorkoutSet) {
        addSet(reps: set.reps, weight: set.weightLbs)
    }

    /// Optimistic delete with a 5-second undo window.
    func delete(_ set: WorkoutSet) {
        guard set.id > 0 else { return }
        guard let idx = todaySets.firstIndex(where: { $0.id == set.id }) else { return }
        lastDeleted = (set, idx)
        withAnimation { todaySets.remove(at: idx) }
        toast = Toast(message: "Set deleted", actionLabel: "Undo")

        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try await self.client?.deleteSet(id: set.id)
            } catch {
                self.toast = Toast(message: "Delete failed — restored", isError: true)
            }
            self.pendingDeletes[set.id] = nil
            await self.refresh(prefill: false)
        }
        pendingDeletes[set.id] = task
    }

    func undoDelete() {
        guard let (set, idx) = lastDeleted else { return }
        pendingDeletes[set.id]?.cancel()
        pendingDeletes[set.id] = nil
        lastDeleted = nil
        withAnimation {
            todaySets.insert(set, at: min(idx, todaySets.count))
        }
    }

    /// Immediate server delete (used by the day-summary sheet, where sets may
    /// belong to any exercise — no undo window).
    func deleteImmediate(_ set: WorkoutSet) async {
        guard let client else { return }
        do {
            try await client.deleteSet(id: set.id)
            await refresh(prefill: false)
        } catch {
            toast = Toast(message: "Delete failed — \(error.localizedDescription)", isError: true)
        }
    }

    func update(_ set: WorkoutSet, reps: Int, weight: Double?) async {
        guard let client else { return }
        do {
            let updated = try await client.updateSet(id: set.id, reps: reps, weightLbs: weight)
            if let idx = todaySets.firstIndex(where: { $0.id == set.id }) {
                todaySets[idx] = updated
            }
            await refresh(prefill: false)
        } catch {
            toast = Toast(message: "Update failed — \(error.localizedDescription)", isError: true)
        }
    }
}
