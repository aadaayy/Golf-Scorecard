import SwiftUI

/// Find Courses: search the online course library by name or town and
/// download a course onto the phone, where it then works with no signal.
///
/// Upright it's one list. Open on the Duo or sideways, the list sits on the
/// left and the picked course on the right: its tees and a Download button,
/// or, once it's on the phone, the whole course with Play.
struct FindCoursesView: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var query = ""
    @State private var pickedID: String?

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var results: [CourseIndex.Entry] { catalog.index?.search(query) ?? [] }
    private var picked: CourseIndex.Entry? {
        results.first { $0.id == pickedID } ?? results.first
    }

    var body: some View {
        Group {
            if isWide, let entry = picked {
                WideRoundLayout(card: list, map: detail(entry))
            } else {
                list
            }
        }
        .navigationTitle("Find Courses")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Course name or town")
        .task {
            if catalog.index == nil { await catalog.load() }
        }
    }

    @ViewBuilder
    private var list: some View {
        switch catalog.state {
        case .notLoaded, .loading:
            ProgressView("Loading courses…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Can't Reach the Course Library", systemImage: "wifi.slash")
            } description: {
                Text("Check your signal and try again. Courses already on your phone still work.")
            } actions: {
                Button("Try Again") { Task { await catalog.load() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library-retry")
            }
        case .loaded:
            List {
                Section {
                    ForEach(results) { entry in
                        row(entry)
                    }
                } footer: {
                    if !results.isEmpty {
                        Text("Downloaded courses work with no signal.")
                    }
                }
            }
            .refreshable { await catalog.load() }
            .overlay {
                if results.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("No courses yet", systemImage: "flag", description: Text("Courses added to the library show up here."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: CourseIndex.Entry) -> some View {
        let label = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.headline).foregroundStyle(.primary)
                Text("\(entry.town) · \(entry.holes) holes · Par \(entry.par)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if catalog.failed.contains(entry.id) {
                    Text("Download didn't finish. Tap to try again.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            CourseDownloadStatus(entry: entry)
        }
        .contentShape(Rectangle())

        Group {
            if isWide {
                Button {
                    pickedID = entry.id
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .listRowBackground(entry.id == picked?.id ? Color.accentColor.opacity(0.12) : nil)
            } else if let course = library.course(id: entry.id), !entry.isNewer(than: course.currentVersion) {
                // On the phone: straight to starting a round.
                NavigationLink(value: course) { label }
            } else {
                Button {
                    Task { await catalog.download(entry, into: library) }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .disabled(catalog.downloading.contains(entry.id))
            }
        }
        .accessibilityIdentifier("library-course-\(entry.id)")
        .swipeActions {
            if library.isDownloaded(entry.id) {
                Button("Remove", systemImage: "trash", role: .destructive) {
                    library.remove(entry.id)
                }
            }
        }
    }

    /// The picked course on the right half.
    @ViewBuilder
    private func detail(_ entry: CourseIndex.Entry) -> some View {
        if let course = library.course(id: entry.id), !entry.isNewer(than: course.currentVersion) {
            CoursePreview(course: course)
        } else {
            LibraryCourseDetail(entry: entry)
        }
    }
}

/// Download, a spinner while it downloads, Update when the library has a
/// newer copy, or a tick once it's on the phone. In a list row it's only the
/// sign (the row is the button); on the right half it's the Download button.
struct CourseDownloadStatus: View {
    let entry: CourseIndex.Entry
    /// The big button on the right half, instead of the small icon in a row.
    var large = false

    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog

    var body: some View {
        let installed = library.installedVersion(of: entry.id)
        if catalog.downloading.contains(entry.id) {
            ProgressView()
                .controlSize(large ? .large : .regular)
                .accessibilityLabel("Downloading")
                .accessibilityIdentifier("downloading-\(entry.id)")
        } else if let installed, !entry.isNewer(than: installed) {
            Group {
                if large {
                    Label("On Your Phone", systemImage: "checkmark.circle.fill").font(.headline)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .accessibilityLabel("On your phone")
                }
            }
            .foregroundStyle(.green)
            .accessibilityIdentifier("downloaded-\(entry.id)")
        } else {
            let isUpdate = installed != nil
            if large {
                Button {
                    Task { await catalog.download(entry, into: library) }
                } label: {
                    Label(isUpdate ? "Update · \(entry.sizeText)" : "Download · \(entry.sizeText)",
                          systemImage: isUpdate ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        .font(.headline)
                        .frame(maxWidth: 360)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(isUpdate ? "update-\(entry.id)" : "download-\(entry.id)")
            } else {
                // In a row the whole row is the button, so this is just the sign.
                Image(systemName: isUpdate ? "arrow.triangle.2.circlepath.circle" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(isUpdate ? "Update" : "Download")
            }
        }
    }
}

/// A library course that isn't on the phone yet: what it is, and Download.
struct LibraryCourseDetail: View {
    let entry: CourseIndex.Entry

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "flag.and.flag.filled.crossed")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 4) {
                Text(entry.name).font(.title2.bold()).multilineTextAlignment(.center)
                Text(entry.town).foregroundStyle(.secondary)
                Text("\(entry.holes) holes · Par \(entry.par)").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(entry.tees, id: \.self) { tee in
                    let style = TeeStyle.row(for: tee)
                    VStack(spacing: 0) {
                        Text(tee).font(.caption.weight(.semibold))
                        if let yards = entry.yards[tee] {
                            Text("\(yards)").font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(style.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(style.band, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CardColors.edge, lineWidth: 0.5))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            CourseDownloadStatus(entry: entry, large: true)
            Text("Once it's downloaded, the course works with no signal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-detail")
    }
}
