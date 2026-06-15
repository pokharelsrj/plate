import SwiftUI

struct ExercisesView: View {
    @Environment(Session.self) private var session

    @State private var exercises: [Exercise] = []
    @State private var bodyPartTags: [BodyPartTag] = []
    @State private var loaded = false
    @State private var error: String?

    @State private var showTags = false
    @State private var newTagName = ""
    @State private var newExerciseName = ""
    @State private var newExerciseBodyPart = "chest"
    @State private var editingExercise: Exercise?
    @State private var toast: Toast?

    private var bodyPartNames: [String] { bodyPartTags.map(\.name) }

    private var groups: [(bodyPart: String, exercises: [Exercise])] {
        var buckets: [String: [Exercise]] = [:]
        for e in exercises {
            buckets[e.bodyPart ?? "uncategorized", default: []].append(e)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0]!) }
    }

    var body: some View {
        List {
            tagsSection
            newExerciseSection
            ForEach(groups, id: \.bodyPart) { group in
                Section {
                    ForEach(group.exercises) { exercise in
                        row(exercise)
                    }
                } header: {
                    Eyebrow(group.bodyPart)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.piBg)
        .navigationTitle("Exercises")
        .task { await load() }
        .refreshable { await load() }
        .toast($toast)
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditSheet(exercise: exercise, bodyParts: bodyPartNames) { name, bodyPart in
                Task {
                    do {
                        _ = try await session.client.updateExercise(id: exercise.id, name: name, bodyPart: bodyPart)
                        await load()
                    } catch {
                        toast = Toast(message: error.localizedDescription, isError: true)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        HStack {
            Text(exercise.name)
                .font(.piBody)
                .foregroundStyle(Color.piText)
            Spacer()
            Text("\(exercise.setCount ?? 0) sets")
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
        }
        .listRowBackground(Color.piBg2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    do {
                        try await session.client.deleteExercise(id: exercise.id)
                        await load()
                    } catch {
                        toast = Toast(message: error.localizedDescription, isError: true)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled((exercise.setCount ?? 0) > 0)
            Button {
                editingExercise = exercise
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.piGymCyan)
        }
    }

    private var tagsSection: some View {
        Section {
            DisclosureGroup("Body-part tags", isExpanded: $showTags) {
                FlowLayout(spacing: 8) {
                    ForEach(bodyPartTags) { tag in
                        HStack(spacing: 6) {
                            Text(tag.name)
                                .font(.piSubheadline)
                            if tag.exerciseCount == 0 {
                                Button {
                                    Task {
                                        do {
                                            try await session.client.deleteBodyPart(name: tag.name)
                                            await load()
                                        } catch {
                                            toast = Toast(message: error.localizedDescription, isError: true)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.piCaption)
                                        .foregroundStyle(Color.piTextMuted)
                                }
                            } else {
                                Text("\(tag.exerciseCount)")
                                    .font(.piCaption)
                                    .foregroundStyle(Color.piTextMuted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.piBg3)
                        .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 6)
                HStack {
                    TextField("New tag", text: $newTagName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        let name = newTagName.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !name.isEmpty else { return }
                        Task {
                            do {
                                try await session.client.createBodyPart(name: name)
                                newTagName = ""
                                await load()
                            } catch {
                                toast = Toast(message: error.localizedDescription, isError: true)
                            }
                        }
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .foregroundStyle(Color.piText)
        }
        .listRowBackground(Color.piBg2)
    }

    private var newExerciseSection: some View {
        Section {
            TextField("Exercise name", text: $newExerciseName)
            Picker("Body part", selection: $newExerciseBodyPart) {
                ForEach(bodyPartNames, id: \.self) { Text($0).tag($0) }
            }
            Button("Add exercise") {
                let name = newExerciseName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        _ = try await session.client.createExercise(name: name, bodyPart: newExerciseBodyPart)
                        newExerciseName = ""
                        await load()
                    } catch {
                        toast = Toast(message: error.localizedDescription, isError: true)
                    }
                }
            }
            .disabled(newExerciseName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Eyebrow("New exercise")
        }
        .listRowBackground(Color.piBg2)
    }

    private func load() async {
        do {
            let resp = try await session.client.exercises()
            let tags = try await session.client.bodyParts()
            exercises = resp.exercises
            bodyPartTags = tags.bodyParts
            if !bodyPartNames.contains(newExerciseBodyPart), let first = bodyPartNames.first {
                newExerciseBodyPart = first
            }
            loaded = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

struct ExerciseEditSheet: View {
    let exercise: Exercise
    let bodyParts: [String]
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bodyPart: String

    init(exercise: Exercise, bodyParts: [String], onSave: @escaping (String, String) -> Void) {
        self.exercise = exercise
        self.bodyParts = bodyParts
        self.onSave = onSave
        _name = State(initialValue: exercise.name)
        _bodyPart = State(initialValue: exercise.bodyPart ?? bodyParts.first ?? "other")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Body part", selection: $bodyPart) {
                    ForEach(bodyParts, id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), bodyPart)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
