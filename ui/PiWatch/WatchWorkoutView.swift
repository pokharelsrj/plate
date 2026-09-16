import SwiftUI
import Observation
import WatchKit

@MainActor
@Observable
final class WatchWorkoutVM {
    var exercises: [Exercise] = []
    var active: WorkoutActive?
    var todaySets: [WorkoutSet] = []
    var reps = 10
    var weight = 0.0
    var weightStep: Double = 5
    var restStartedAt: Date?
    var errorMessage: String?
    var isAdding = false
    private var manualRestMark = false

    var selectedBodyPart: String = ""

    var bodyParts: [String] {
        var seen = Set<String>()
        var parts: [String] = []
        for e in exercises {
            if let bp = e.bodyPart, !seen.contains(bp) {
                seen.insert(bp)
                parts.append(bp)
            }
        }
        return parts.sorted()
    }

    var filteredExercises: [Exercise] {
        selectedBodyPart.isEmpty ? exercises : exercises.filter { $0.bodyPart == selectedBodyPart }
    }

    var activePR: ExercisePR? {
        guard let active else { return nil }
        return exercises.first(where: { $0.id == active.exerciseId })?.pr
    }

    func cycleWeightStep() {
        switch weightStep {
        case 2.5: weightStep = 5
        case 5:   weightStep = 10
        default:  weightStep = 2.5
        }
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    func load() async {
        do {
            exercises = try await WatchAPI.shared.exercises().exercises
            let saved = Int64(UserDefaults.standard.integer(forKey: "watch.activeExercise"))
            if saved > 0, exercises.contains(where: { $0.id == saved }) {
                try await select(exerciseId: saved)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(exerciseId: Int64) async throws {
        let resp = try await WatchAPI.shared.workout(date: today, exerciseId: exerciseId)
        active = resp.active
        todaySets = resp.active?.todaySets ?? []
        if let a = resp.active {
            reps = a.prefillReps
            weight = a.prefillWeightLbs ?? 0
        }
        UserDefaults.standard.set(Int(exerciseId), forKey: "watch.activeExercise")
        errorMessage = nil
    }

    func addSet(reps repsIn: Int? = nil, weight weightIn: Double?? = nil) async {
        guard let active else { return }
        isAdding = true
        defer { isAdding = false }
        let r = repsIn ?? reps
        let w: Double? = weightIn ?? (weight > 0 ? weight : nil)
        do {
            let set = try await WatchAPI.shared.addSet(date: today, exerciseId: active.exerciseId,
                                                       reps: r, weightLbs: w)
            todaySets.append(set)
            if manualRestMark {
                manualRestMark = false
            } else {
                startRest()
            }
            errorMessage = nil
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// One-tap clone of the most recent set (today's last, else last session's).
    func repeatLast() async {
        if let last = todaySets.last {
            await addSet(reps: last.reps, weight: last.weightLbs)
        } else if let last = active?.lastSessionSets.last {
            await addSet(reps: last.reps, weight: last.weightLbs)
        }
    }

    var canRepeatLast: Bool {
        !(todaySets.isEmpty && (active?.lastSessionSets.isEmpty ?? true))
    }

    /// "10×135 · 8×140" reference line from the previous session.
    var lastSessionSummary: String? {
        guard let sets = active?.lastSessionSets, !sets.isEmpty else { return nil }
        return sets.map { s in
            if let w = s.weightLbs {
                let num = w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
                return "\(s.reps)×\(num)"
            }
            return "\(s.reps)"
        }.joined(separator: " · ")
    }

    func markSetDone() {
        startRest()
        manualRestMark = true
    }

    func completeExercise() {
        restStartedAt = nil
        manualRestMark = false
        WatchAPI.shared.notifyTimerEnded()
    }

    private func startRest() {
        restStartedAt = Date()
        WatchAPI.shared.notifyTimerStarted(restStartedAt!, exercise: active?.exerciseName ?? "Workout")
    }
}

struct WatchWorkoutView: View {
    @State private var vm = WatchWorkoutVM()

    var body: some View {
        NavigationStack {
            Group {
                if let active = vm.active {
                    activePanel(active)
                } else {
                    exerciseList
                }
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Active exercise

    private func activePanel(_ active: WorkoutActive) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if let start = vm.restStartedAt {
                    VStack(spacing: 2) {
                        Text("REST")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(start, style: .timer)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Button {
                            vm.markSetDone()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Button {
                            vm.completeExercise()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .tint(.orange)
                    }
                } else {
                    Button {
                        vm.markSetDone()
                    } label: {
                        Label("Set done", systemImage: "timer")
                    }
                    .tint(.orange)
                }

                Divider()

                if let pr = vm.activePR {
                    Text(pr.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }

                stepperRow(label: "reps",
                           value: "\(vm.reps)",
                           minus: { vm.reps = max(1, vm.reps - 1) },
                           plus: { vm.reps += 1 })

                HStack(spacing: 0) {
                    stepperRow(label: "lb",
                               value: vm.weight > 0 ? weightLabel(vm.weight) : "—",
                               minus: { vm.weight = max(0, vm.weight - vm.weightStep) },
                               plus: { vm.weight += vm.weightStep })
                }
                Button {
                    vm.cycleWeightStep()
                } label: {
                    Text("Step: \(weightLabel(vm.weightStep)) lb")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await vm.addSet() }
                } label: {
                    if vm.isAdding {
                        ProgressView()
                    } else {
                        Label("Add set", systemImage: "plus")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(vm.isAdding)

                Button {
                    Task { await vm.repeatLast() }
                } label: {
                    Label("Repeat last", systemImage: "arrow.counterclockwise")
                }
                .disabled(vm.isAdding || !vm.canRepeatLast)

                Text("\(vm.todaySets.count) sets")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let last = vm.lastSessionSummary {
                    Text("Last: \(last)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                NavigationLink("Change exercise") {
                    exerciseList
                }
                .font(.footnote)
            }
        }
        .navigationTitle(vm.active?.exerciseName ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepperRow(label: String, value: String,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Button(action: minus) {
                Image(systemName: "minus")
            }
            .frame(width: 38)
            Spacer()
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: plus) {
                Image(systemName: "plus")
            }
            .frame(width: 38)
        }
        .buttonStyle(.bordered)
    }

    private func weightLabel(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    // MARK: - Exercise picker

    private var exerciseList: some View {
        List {
            if vm.exercises.isEmpty {
                VStack(spacing: 6) {
                    Text(vm.errorMessage ?? "No exercises")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await vm.load() }
                    }
                }
            }
            if !vm.bodyParts.isEmpty {
                Picker("Filter", selection: $vm.selectedBodyPart) {
                    Text("All").tag("")
                    ForEach(vm.bodyParts, id: \.self) { bp in
                        Text(bp.capitalized).tag(bp)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            ForEach(vm.filteredExercises) { exercise in
                Button {
                    Task { try? await vm.select(exerciseId: exercise.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let bp = exercise.bodyPart {
                                Text(bp)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            if let pr = exercise.pr {
                                Text(pr.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercises")
    }
}
