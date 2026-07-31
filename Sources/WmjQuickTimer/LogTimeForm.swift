import WmjQuickTimerCore
import SwiftUI

/// Type-ahead project search: matches drop down under the field, Return picks
/// the top one. Replaces a separate filter box + long Picker menu.
struct ProjectField: View {
    let projects: [Project]
    @Binding var project: Project?

    @State private var query = ""
    @FocusState private var focused: Bool

    private static func label(_ p: Project) -> String { "\(p.projectNumber) - \(p.projectName)" }

    private var matches: [Project] {
        guard query != project.map(Self.label) else { return [] }
        guard !query.isEmpty else { return projects }   // empty field = browse everything
        return projects.filter {
            Self.label($0).localizedCaseInsensitiveContains(query)
                || $0.clientName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                TextField("Search projects…", text: $query)
                    .onAppear { syncQueryToSelection() }
                    .onChange(of: project) { syncQueryToSelection() }
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { matches.first.map(pick) }
                if project != nil {
                    Button {
                        project = nil
                        query = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear project")
                }
            }

            if focused, !matches.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { p in
                            Button { pick(p) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Self.label(p)).lineLimit(2)
                                    Text(p.clientName).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(.background.secondary, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }
        }
    }

    /// A selection made before this view appeared (demo pre-fill) should show
    /// in the field, not a blank placeholder.
    private func syncQueryToSelection() {
        if let project, query.isEmpty { query = Self.label(project) }
    }

    private func pick(_ p: Project) {
        project = p
        query = Self.label(p)
        focused = false
    }
}

/// Project → task → service selection, shared by Quick Log (with hours field)
/// and Start Timer (without). Each instance keeps its own draft, so Quick Log
/// stays usable while a timer runs.
struct LogTimeForm: View {
    @Environment(AppModel.self) private var model

    let submitLabel: String
    let showsHours: Bool
    let onSubmit: (TaskSelection, Double, Date) async throws -> Void

    @State private var project: Project?
    @State private var tasks: [WMJTask] = []
    @State private var task: WMJTask?
    @State private var serviceCode = ""
    @State private var hours = 1.0
    @State private var workDate = Date()
    @State private var busy = false
    @State private var error: String?
    @State private var confirmation: String?

    private var selection: TaskSelection? {
        guard let project, let task, !serviceCode.isEmpty else { return nil }
        return TaskSelection(projectNumber: project.projectNumber, projectName: project.projectName,
                             taskID: task.taskIDString, taskName: task.taskName,
                             serviceCode: serviceCode)
    }

    private var canSubmit: Bool {
        selection != nil && (!showsHours || TimeMath.isValidQuickLogHours(hours)) && !busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Fixed-width label column, controls fill the rest.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    // Top-anchored so the label stays put when the search
                    // dropdown expands the row.
                    Text("Project")
                        .gridCellAnchor(.topLeading)
                        .padding(.top, 4)
                    ProjectField(projects: model.projects, project: $project)
                        .onChange(of: project) { loadTasks() }
                }
                GridRow {
                    Text("Task")
                    Picker("Task", selection: $task) {
                        Text(project == nil ? "Select a project first" : "Select…").tag(WMJTask?.none)
                        ForEach(tasks) { t in
                            Text(t.taskName).tag(Optional(t))
                        }
                    }
                    .labelsHidden()
                    .disabled(tasks.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Service")
                    Picker("Service", selection: $serviceCode) {
                        Text("Select…").tag("")
                        ForEach(model.services) { s in
                            Text(s.description).tag(s.serviceCode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if showsHours {
                    GridRow {
                        Text("Hours")
                        HStack {
                            TextField("Hours", value: $hours, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Stepper("", value: $hours, in: 0.25...8, step: 0.25)
                                .labelsHidden()
                            if !TimeMath.isValidQuickLogHours(hours) {
                                Text("0.25–8 in ¼ steps")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    GridRow {
                        Text("Date")
                        DatePicker("Date", selection: $workDate, displayedComponents: .date)
                            .labelsHidden()
                            .fixedSize()
                    }
                }
            }

            HStack {
                Button(submitLabel) { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                if busy { ProgressView().controlSize(.small) }
                if let confirmation {
                    Text(confirmation).font(.caption).foregroundStyle(.green)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            if serviceCode.isEmpty { serviceCode = model.defaultServiceCode }
            // Demo screenshots show a filled form, not an empty one.
            if AppModel.demo, project == nil { project = model.projects.first }
        }
    }

    private func loadTasks() {
        task = nil
        tasks = []
        guard let project else { return }
        Task {
            do {
                tasks = try await model.tasks(projectKey: project.projectKey)
                if tasks.count == 1 { task = tasks.first }
                if AppModel.demo, task == nil { task = tasks.first }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard let selection else { return }
        busy = true
        error = nil
        confirmation = nil
        Task {
            defer { busy = false }
            do {
                try await onSubmit(selection, hours, workDate)
                confirmation = "Logged ✓"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
