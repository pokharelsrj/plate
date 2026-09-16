import SwiftUI

struct WorkoutView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm = WorkoutViewModel()

    @State private var editingSet: WorkoutSet?
    @State private var todayCollapsed = false
    @State private var addedTrigger = 0
    @State private var showDaySummary = false

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if vm.active != nil {
                    activePanelSection
                    todaySection
                    lastSessionSection
                }
                pickerSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.piBg)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        WorkoutStatsView()
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showDaySummary = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .disabled(vm.groups.isEmpty)
                }
            }
            .sheet(isPresented: $showDaySummary) {
                DaySummarySheet(vm: vm)
            }
            .task {
                vm.session = session
                vm.startObservingWatch()
                await vm.load()
                vm.restoreRestTimer()
            }
            .animation(.snappy, value: vm.restStartedAt)
            .onAppear {
                Task { await vm.snapToTodayIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    vm.restoreRestTimer()
                    Task { await vm.snapToTodayIfNeeded() }
                }
            }
            .refreshable { await vm.refresh(prefill: false) }
            .toast(Binding(get: { vm.toast }, set: { vm.toast = $0 })) {
                vm.undoDelete()
            }
            .sheet(item: $editingSet) { set in
                EditSetSheet(set: set) { reps, weight in
                    Task { await vm.update(set, reps: reps, weight: weight) }
                }
                .presentationDetents([.height(360)])
            }
            .sensoryFeedback(.success, trigger: addedTrigger)
        }
    }

    // MARK: - Header (date nav + stats)

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                // Buttons in a List row need explicit styles, otherwise a tap
                // anywhere in the row fires every button at once.
                HStack {
                    Button {
                        Task { await vm.changeDate(by: -1) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.piPressable)
                    .foregroundStyle(Color.piPrimary)
                    Spacer()
                    Button {
                        Task { await vm.goToToday() }
                    } label: {
                        Text(vm.date == PiDate.todayString ? "Today" : PiDate.shortLabel(vm.date))
                            .font(.piTitle2)
                            .foregroundStyle(vm.date == PiDate.todayString ? Color.piText : Color.piWarn)
                    }
                    .buttonStyle(.piPressable)
                    Spacer()
                    Button {
                        Task { await vm.changeDate(by: 1) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.piPressable)
                    .foregroundStyle(Color.piPrimary)
                }

                Text("\(vm.groups.count) exercises · \(vm.totalSets) sets")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)

                if vm.date != PiDate.todayString {
                    Button {
                        Task { await vm.goToToday() }
                    } label: {
                        Label("Jump to today", systemImage: "arrow.uturn.forward")
                            .font(.piSubheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.piPrimary)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Active exercise panel

    @ViewBuilder
    private var activePanelSection: some View {
        if let active = vm.active {
            Section {
                VStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text(active.exerciseName)
                            .font(.piTitle)
                            .foregroundStyle(Color.piText)
                        if let bp = active.bodyPart {
                            Eyebrow(bp, color: .piWorkoutGold)
                        }
                    }

                    restTimerBar

                    GymStepper(value: Binding(get: { vm.reps }, set: { vm.reps = $0 }),
                               step: 1, suffix: "reps", minimum: 1)

                    HStack(spacing: 8) {
                        GymStepper(value: Binding(get: { vm.weight }, set: { vm.weight = $0 }),
                                   step: vm.weightStep, suffix: "lb")
                        Menu {
                            ForEach([2.5, 5.0, 10.0], id: \.self) { step in
                                Button {
                                    vm.weightStep = step
                                } label: {
                                    if vm.weightStep == step {
                                        Label(stepLabel(step), systemImage: "checkmark")
                                    } else {
                                        Text(stepLabel(step))
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.piTextMuted)
                                .frame(width: 36, height: 56)
                        }
                    }

                    Button {
                        vm.addSet()
                        addedTrigger += 1
                    } label: {
                        Label("ADD SET", systemImage: "plus")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(Color.piPrimary)
                            .foregroundStyle(Color.piOnPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.piPressable)

                    HStack(spacing: 8) {
                        // Tap the instant the physical set ends — rest starts
                        // counting now; entering the numbers won't reset it.
                        Button {
                            vm.markSetDone()
                            addedTrigger += 1
                        } label: {
                            Label("Set done", systemImage: "timer")
                                .font(.piHeadline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.piWorkoutGold.opacity(0.15))
                                .foregroundStyle(Color.piWorkoutGold)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(vm.date != PiDate.todayString)
                        .buttonStyle(.piPressable)

                        Button {
                            vm.repeatLast()
                            addedTrigger += 1
                        } label: {
                            Label("Repeat last", systemImage: "arrow.counterclockwise")
                                .font(.piHeadline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.piBg3)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .foregroundStyle(vm.canRepeatLast ? Color.piPrimary : Color.piTextMuted)
                        .disabled(!vm.canRepeatLast)
                        .buttonStyle(.piPressable)
                    }
                }
                .piCard()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    /// Count-up rest stopwatch — appears after the first set, resets on every
    /// new set, dismissed by "Done", resumable after an accidental "Done".
    @ViewBuilder
    private var restTimerBar: some View {
        if let start = vm.restStartedAt {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .foregroundStyle(Color.piWorkoutGold)
                Eyebrow("Rest", color: .piWorkoutGold)
                Text(start, style: .timer)
                    .font(.piMetricMed)
                    .monospacedDigit()
                    .foregroundStyle(Color.piText)
                Spacer()
                Button {
                    vm.markSetDone()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.piSubheadline)
                        .fontWeight(.semibold)
                        .padding(8)
                        .background(Color.piBg3)
                        .foregroundStyle(Color.piTextMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.piPressable)
                Button {
                    vm.completeExercise()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.piSubheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.piWorkoutGold.opacity(0.18))
                        .foregroundStyle(Color.piWorkoutGold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.piPressable)
                .sensoryFeedback(.success, trigger: vm.restStartedAt == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.piWorkoutGold.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.piWorkoutGold.opacity(0.35), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if vm.canResumeRest {
            Button {
                vm.resumeRestTimer()
            } label: {
                Label("Resume rest timer", systemImage: "arrow.uturn.backward.circle")
                    .font(.piSubheadline)
                    .foregroundStyle(Color.piTextMuted)
            }
            .buttonStyle(.piPressable)
        }
    }

    private func stepLabel(_ step: Double) -> String {
        step.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(step)) lb" : String(format: "%.1f lb", step)
    }

    // MARK: - Today's sets

    @ViewBuilder
    private var todaySection: some View {
        if !vm.todaySets.isEmpty {
            Section {
                if !todayCollapsed {
                    ForEach(Array(vm.todaySets.enumerated()), id: \.element.id) { index, set in
                        SetRow(index: index + 1, set: set) {
                            editingSet = set
                        }
                        .listRowBackground(Color.piBg2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.delete(set)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                vm.duplicate(set)
                                addedTrigger += 1
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.piPrimary)
                        }
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) { todayCollapsed.toggle() }
                } label: {
                    HStack {
                        Eyebrow("Today · \(vm.todaySets.count) sets")
                        Spacer()
                        Image(systemName: todayCollapsed ? "chevron.down" : "chevron.up")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                    }
                }
                .buttonStyle(.piPressable)
            }
        }
    }

    // MARK: - Last session

    @ViewBuilder
    private var lastSessionSection: some View {
        if let active = vm.active, !active.lastSessionSets.isEmpty {
            Section {
                ForEach(Array(active.lastSessionSets.enumerated()), id: \.element.id) { index, set in
                    Button {
                        vm.cloneFromLastSession(set)
                        addedTrigger += 1
                    } label: {
                        HStack {
                            SetRowLabel(index: index + 1, set: set, muted: true)
                            Spacer()
                            Image(systemName: "arrow.uturn.left.circle")
                                .foregroundStyle(Color.piPrimary)
                        }
                    }
                    .listRowBackground(Color.piBg2.opacity(0.6))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            vm.cloneFromLastSession(set)
                            addedTrigger += 1
                        } label: {
                            Label("Clone", systemImage: "plus.square.on.square")
                        }
                        .tint(.piPrimary)
                    }
                }
            } header: {
                Eyebrow("Last · \(active.lastSessionDate.map(PiDate.shortLabel) ?? "") — tap to clone")
            }
        }
    }

    // MARK: - Exercise picker

    private var pickerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.piTextMuted)
                    TextField("Search exercises…", text: Binding(get: { vm.searchText }, set: { vm.searchText = $0 }))
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Color.piBg3)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if vm.filteredPickerGroups.isEmpty {
                    VStack(spacing: 8) {
                        Text("No exercises match")
                            .font(.piSubheadline)
                            .foregroundStyle(Color.piTextMuted)
                        NavigationLink("Manage library →") {
                            ExercisesView()
                        }
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(vm.filteredPickerGroups, id: \.bodyPart) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(group.bodyPart)
                            FlowLayout(spacing: 8) {
                                ForEach(group.exercises) { exercise in
                                    exerciseTile(exercise)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    NavigationLink {
                        ExercisesView()
                    } label: {
                        Label("Manage library", systemImage: "books.vertical")
                            .font(.piSubheadline)
                            .foregroundStyle(Color.piTextMuted)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func exerciseTile(_ exercise: Exercise) -> some View {
        let isActive = vm.active?.exerciseId == exercise.id
        return Button {
            Task { await vm.selectExercise(exercise) }
        } label: {
            Text(exercise.name)
                .font(.piSubheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isActive ? Color.piPrimary : Color.piBg3)
                .foregroundStyle(isActive ? Color.piOnPrimary : Color.piText)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isActive ? Color.clear : Color.piBorder, lineWidth: 1))
        }
        .buttonStyle(.piPressable)
        .sensoryFeedback(.selection, trigger: isActive)
    }
}

// MARK: - Rows

struct SetRowLabel: View {
    let index: Int
    let set: WorkoutSet
    var muted = false

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(index)")
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
                .frame(width: 28, alignment: .leading)
            Text("\(set.reps) × \(weightLabel)")
                .font(.piBody)
                .foregroundStyle(muted ? Color.piTextMuted : Color.piText)
        }
    }

    private var weightLabel: String {
        guard let w = set.weightLbs else { return "bodyweight" }
        let num = w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
        return "\(num) lb"
    }
}

struct SetRow: View {
    let index: Int
    let set: WorkoutSet
    let onEdit: () -> Void

    var body: some View {
        HStack {
            SetRowLabel(index: index, set: set)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(Color.piTextMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.piPressable)
        }
        .opacity(set.id < 0 ? 0.5 : 1)   // optimistic insert pending server confirm
    }
}

// MARK: - Edit sheet

struct EditSetSheet: View {
    let set: WorkoutSet
    let onSave: (Int, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reps: Double
    @State private var weight: Double

    init(set: WorkoutSet, onSave: @escaping (Int, Double?) -> Void) {
        self.set = set
        self.onSave = onSave
        _reps = State(initialValue: Double(set.reps))
        _weight = State(initialValue: set.weightLbs ?? 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GymStepper(value: $reps, step: 1, suffix: "reps", minimum: 1)
                GymStepper(value: $weight, step: 5, suffix: "lb")
                Text("Set weight to 0 for bodyweight")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
                Spacer()
            }
            .padding(20)
            .background(Color.piBg)
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Int(reps), weight > 0 ? weight : nil)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Day summary sheet

/// Full list of the day's work grouped by exercise. Tap a header to make that
/// exercise active; rows support edit (tap) and delete (swipe).
struct DaySummarySheet: View {
    @Bindable var vm: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingSet: WorkoutSet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(vm.groups.count) exercises · \(vm.totalSets) sets")
                            .font(.piSubheadline)
                            .foregroundStyle(Color.piTextMuted)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(vm.groups) { group in
                    Section {
                        ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                            Button {
                                editingSet = set
                            } label: {
                                HStack {
                                    SetRowLabel(index: index + 1, set: set)
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.piBg2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteImmediate(set) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Button {
                            if let exercise = vm.exercises.first(where: { $0.id == group.exerciseId }) {
                                Task { await vm.selectExercise(exercise) }
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Eyebrow("\(group.exerciseName) · \(group.sets.count) sets",
                                        color: vm.active?.exerciseId == group.exerciseId ? .piPrimary : .piTextMuted)
                                Spacer()
                                Image(systemName: "target")
                                    .font(.piCaption)
                                    .foregroundStyle(Color.piTextMuted)
                            }
                        }
                        .buttonStyle(.piPressable)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.piBg)
            .navigationTitle(vm.date == PiDate.todayString ? "Today's workout" : PiDate.shortLabel(vm.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingSet) { set in
                EditSetSheet(set: set) { reps, weight in
                    Task { await vm.update(set, reps: reps, weight: weight) }
                }
                .presentationDetents([.height(360)])
            }
        }
    }
}

// MARK: - Flow layout for picker tiles

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
