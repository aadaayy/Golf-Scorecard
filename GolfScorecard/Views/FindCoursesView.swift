import SwiftUI

/// Find Courses: search the online course library by name or town and
/// download a course onto the phone, where it then works with no signal.
///
/// Upright it's one list. Open on the Duo or sideways, the list sits on the
/// left and the picked course on the right: its tees and a Download button,
/// or, once it's on the phone, the whole course with Play.
///
/// List | Map at the top switches to a map with a dot for every course, for
/// finding courses somewhere you don't know their names. The search narrows
/// the dots too. Tapping a dot shows the course in a card at the bottom, or
/// on the right half when the phone is open or sideways.
struct FindCoursesView: View {
    @Environment(CourseLibrary.self) private var library
    @Environment(CourseCatalog.self) private var catalog
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var query = ""
    @State private var pickedID: String?
    @AppStorage(SettingsKey.findCoursesOnMap) private var showsMap = false
    @State private var mapPickedID: String?
    /// Courses at one spot on the map, waiting for the golfer to pick one.
    @State private var stackedIDs: [String] = []

    private var isWide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var results: [CourseIndex.Entry] { catalog.index?.search(query) ?? [] }
    private var picked: CourseIndex.Entry? {
        results.first { $0.id == pickedID } ?? results.first
    }
    private var mapEntries: [CourseIndex.Entry] { results.filter(\.hasLocation) }
    private var mapPicked: CourseIndex.Entry? {
        mapEntries.first { $0.id == mapPickedID }
    }

    var body: some View {
        Group {
            if showsMap {
                // Paper behind the map too, so the strips beside and under
                // it (tab bar, side tabs, the card's space) aren't white.
                if isWide {
                    WideRoundLayout(card: map.paperBackground(), map: mapSide)
                } else {
                    map
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if let entry = mapPicked {
                                MapCourseCard(entry: entry) { mapPickedID = nil }
                                    .padding(.top, 12)
                            }
                        }
                        .paperBackground()
                }
            } else if isWide, let entry = picked {
                WideRoundLayout(card: list, map: detail(entry))
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // A sideways phone keeps it in the bar, where the search can't cover it.
            if verticalSizeClass != .compact { viewSwitch }
        }
        .toolbar {
            if verticalSizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    viewPicker.frame(width: 170)
                }
            }
        }
        .onChange(of: query) { mapPickedID = nil }
        .confirmationDialog("Courses at This Spot", isPresented: Binding(
            get: { !stackedIDs.isEmpty },
            set: { if !$0 { stackedIDs = [] } }
        ), titleVisibility: .visible) {
            ForEach(stackedIDs, id: \.self) { id in
                if let entry = catalog.index?.entry(id: id) {
                    Button(entry.name) { mapPickedID = id }
                }
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
                .paperBackground()
        case .failed:
            ContentUnavailableView {
                Label("Can't Reach the Course Library", systemImage: "wifi.slash")
            } description: {
                Text("Check your signal and try again. Courses already on your phone still work.")
            } actions: {
                Button("Try Again") { Task { await catalog.load() } }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Book.paper)
                    .accessibilityIdentifier("library-retry")
            }
            .paperBackground()
        case .loaded:
            List {
                Section {
                    ForEach(results) { entry in
                        row(entry)
                    }
                } footer: {
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Downloaded courses work with no signal.")
                            Text(AppInfo.courseDataCredit)
                                .accessibilityIdentifier("library-credit")
                        }
                    }
                }
            }
            .bookList()
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

    /// List | Map
    private var viewPicker: some View {
        Picker("Show courses as", selection: $showsMap) {
            Text("List").tag(false)
            Text("Map").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("courses-view-switch")
    }

    /// List | Map across the top of the page.
    private var viewSwitch: some View {
        viewPicker
            .frame(maxWidth: 320)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Book.paper)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Book.rule).frame(height: 0.5)
            }
    }

    /// Every course with a location as a dot. While the list is loading or
    /// can't be reached, the same message the list shows.
    @ViewBuilder
    private var map: some View {
        if let index = catalog.index {
            // Stops above the tab bar, so no dot hides under it.
            CourseMapView(entries: mapEntries, pickedID: $mapPickedID, stackedIDs: $stackedIDs, fitKey: query)
                .overlay(alignment: .bottom) { mapEdge.frame(height: 1) }
                .overlay(alignment: .trailing) {
                    // Open, the split already draws this line.
                    if !isWide { mapEdge.frame(width: 1) }
                }
                .overlay(alignment: .top) { mapCaption(index) }
                .overlay {
                    if mapEntries.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .background(Book.paper.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                            .padding(40)
                    }
                }
        } else {
            list
        }
    }

    /// An ink line where the map meets the paper.
    private var mapEdge: some View {
        Rectangle().fill(Book.ink.opacity(0.5))
    }

    /// How many courses are on the map, on a slip of paper at the top.
    private func mapCaption(_ index: CourseIndex) -> some View {
        let left = index.courses.count - index.mapped.count
        var text = query.isEmpty
            ? "\(mapEntries.count) courses · tap a dot"
            : "\(mapEntries.count) found"
        if query.isEmpty && left > 0 {
            text += " · \(left) only in the list"
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Book.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .bookBox(cornerRadius: 8, fill: Book.page.opacity(0.95))
            .padding(.top, 8)
            .accessibilityIdentifier("map-caption")
    }

    /// Open or sideways: the course picked on the map, or how to pick one.
    @ViewBuilder
    private var mapSide: some View {
        if let entry = mapPicked {
            detail(entry)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 48))
                    .foregroundStyle(Book.red)
                Text("Tap a course on the map")
                    .font(Book.title(20, relativeTo: .title3))
                Text("A dot with a number is several courses close together. Tap it to zoom in.")
                    .font(.footnote)
                    .foregroundStyle(Book.pencil)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paperBackground()
            .accessibilityIdentifier("map-hint")
        }
    }

    @ViewBuilder
    private func row(_ entry: CourseIndex.Entry) -> some View {
        let label = HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(Book.title(18, relativeTo: .headline)).foregroundStyle(Book.ink)
                Text("\(entry.town) · \(entry.holes) holes · Par \(entry.par)")
                    .font(.subheadline)
                    .foregroundStyle(Book.pencil)
                if catalog.failed.contains(entry.id) {
                    Text("Download didn't finish. Tap to try again.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Book.red)
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
                .bookRow(marked: entry.id == picked?.id)
            } else if let course = library.course(id: entry.id), !entry.isNewer(than: course.currentVersion) {
                // On the phone: straight to starting a round.
                NavigationLink(value: course) { label }
                    .bookRow()
            } else {
                Button {
                    Task { await catalog.download(entry, into: library) }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .disabled(catalog.downloading.contains(entry.id))
                .bookRow()
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
            .foregroundStyle(Book.leaf)
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
                .foregroundStyle(Book.paper)
                .accessibilityIdentifier(isUpdate ? "update-\(entry.id)" : "download-\(entry.id)")
            } else {
                // In a row the whole row is the button, so this is just the sign.
                Image(systemName: isUpdate ? "arrow.triangle.2.circlepath.circle" : "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(Book.red)
                    .accessibilityLabel(isUpdate ? "Update" : "Download")
            }
        }
    }
}

/// The course picked on the map, in a card at the bottom: what it is, and
/// Download, or Play once it's on the phone.
struct MapCourseCard: View {
    let entry: CourseIndex.Entry
    let close: () -> Void

    @Environment(CourseLibrary.self) private var library

    private var teeLine: String {
        entry.tees.compactMap { tee in entry.yards[tee].map { "\(tee) \($0)" } }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(Book.title(18, relativeTo: .headline))
                        .foregroundStyle(Book.ink)
                        .lineLimit(2)
                    Text("\(entry.town) · \(entry.holes) holes · Par \(entry.par)")
                        .font(.subheadline)
                        .foregroundStyle(Book.pencil)
                    if !teeLine.isEmpty {
                        Text(teeLine)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Book.pencil)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Book.pencil)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("map-card-close")
            }
            if let course = library.course(id: entry.id), !entry.isNewer(than: course.currentVersion) {
                HStack(spacing: 12) {
                    Label("On Your Phone", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Book.leaf)
                        .accessibilityIdentifier("downloaded-\(entry.id)")
                    Spacer(minLength: 0)
                    NavigationLink(value: course) {
                        Label("Play", systemImage: "flag.fill")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Book.paper)
                    .accessibilityIdentifier("map-play-\(entry.id)")
                }
            } else {
                CourseDownloadStatus(entry: entry, large: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .bookBox(cornerRadius: 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-course-card")
    }
}

/// A library course that isn't on the phone yet: what it is, and Download.
struct LibraryCourseDetail: View {
    let entry: CourseIndex.Entry

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "book.pages")
                .font(.system(size: 56))
                .foregroundStyle(Book.ink)
            VStack(spacing: 4) {
                Text(entry.name).font(Book.title(24, relativeTo: .title2)).multilineTextAlignment(.center)
                Text(entry.town).foregroundStyle(Book.pencil)
                Text("\(entry.holes) holes · Par \(entry.par)").foregroundStyle(Book.pencil)
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
            if entry.tees.isEmpty {
                Text("No tee yardages for this course yet")
                    .font(.footnote)
                    .foregroundStyle(Book.pencil)
            }
            CourseDownloadStatus(entry: entry, large: true)
            Text("Once it's downloaded, the course works with no signal.")
                .font(.footnote)
                .foregroundStyle(Book.pencil)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-detail")
    }
}
