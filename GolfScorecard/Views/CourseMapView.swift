import SwiftUI
import MapKit

/// The course library on a map: a red dot for every course that has a
/// location, for finding courses in a town you don't know. Dots close
/// together gather into one numbered dot; tapping it zooms in on them, or,
/// for courses at the same club that never come apart, asks which one.
/// Tapping a course's dot picks it.
///
/// Apple's map, so there's no key and nothing to pay for. Drawn muted and
/// light, with no shops or restaurants, so the red dots stand out like marks
/// in the yardage book.
struct CourseMapView: UIViewRepresentable {
    /// The courses to show (already narrowed by the search).
    let entries: [CourseIndex.Entry]
    @Binding var pickedID: String?
    /// Courses sharing one spot (two courses at one club), to pick from.
    @Binding var stackedIDs: [String]
    /// The map moves to fit the courses whenever this changes (the search text).
    let fitKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator(pickedID: $pickedID, stackedIDs: $stackedIDs)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.overrideUserInterfaceStyle = .light
        map.tintColor = UIColor(Book.red)
        map.showsCompass = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.delegate = context.coordinator
        map.register(CourseDotView.self, forAnnotationViewWithReuseIdentifier: CourseDotView.reuseID)
        map.register(CourseClusterView.self, forAnnotationViewWithReuseIdentifier: CourseClusterView.reuseID)
        map.accessibilityIdentifier = "course-map"
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pickedID = $pickedID
        coordinator.stackedIDs = $stackedIDs

        // Only add and take away the dots that changed, so the map doesn't flicker.
        let wanted = Dictionary(entries.compactMap { entry in
            CourseAnnotation(entry).map { (entry.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let shown = coordinator.annotations
        let gone = shown.filter { wanted[$0.key] == nil }.map(\.value)
        let added = wanted.filter { shown[$0.key] == nil }.map(\.value)
        if !gone.isEmpty { map.removeAnnotations(gone) }
        if !added.isEmpty { map.addAnnotations(added) }
        coordinator.annotations = shown.filter { wanted[$0.key] != nil }.merging(added.map { ($0.id, $0) }) { old, _ in old }

        if coordinator.fittedKey != fitKey || (coordinator.annotations.count > 0 && !coordinator.hasFitted) {
            coordinator.fittedKey = fitKey
            coordinator.hasFitted = !coordinator.annotations.isEmpty
            let annotations = Array(coordinator.annotations.values)
            let animated = coordinator.hasShown
            // Wait a moment the first time, until the map has its size.
            DispatchQueue.main.async { fit(map, to: annotations, animated: animated) }
        }
        coordinator.hasShown = true

        // Keep the map's picked dot the same as the screen's.
        let selected = map.selectedAnnotations.compactMap { $0 as? CourseAnnotation }.first
        if selected?.id != pickedID {
            if let pickedID, let annotation = coordinator.annotations[pickedID] {
                map.selectAnnotation(annotation, animated: true)
            } else if let selected {
                map.deselectAnnotation(selected, animated: true)
            }
        }
    }

    /// Shows every course given, with room around them for the dots.
    private func fit(_ map: MKMapView, to annotations: [CourseAnnotation], animated: Bool) {
        guard !annotations.isEmpty else { return }
        var rect = MKMapRect.null
        for annotation in annotations {
            let point = MKMapPoint(annotation.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // One course, or a few side by side: about two miles across, so the
        // streets around it show.
        let least = MKMapPointsPerMeterAtLatitude(annotations[0].coordinate.latitude) * 3_000
        if rect.width < least || rect.height < least {
            rect = rect.insetBy(dx: -max(0, least - rect.width) / 2, dy: -max(0, least - rect.height) / 2)
        }
        // Room at the top for the caption, and at the bottom for the Maps
        // logo and Legal link, so no dot sits on them.
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 90, right: 40), animated: animated)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var pickedID: Binding<String?>
        var stackedIDs: Binding<[String]>
        var annotations: [String: CourseAnnotation] = [:]
        var fittedKey: String?
        var hasFitted = false
        var hasShown = false

        init(pickedID: Binding<String?>, stackedIDs: Binding<[String]>) {
            self.pickedID = pickedID
            self.stackedIDs = stackedIDs
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: CourseClusterView.reuseID, for: cluster)
            }
            if annotation is CourseAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: CourseDotView.reuseID, for: annotation)
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                let members = cluster.memberAnnotations.compactMap { $0 as? CourseAnnotation }
                if Self.spread(of: members) < 250 {
                    // Courses at one club: zooming in never parts them, so ask which.
                    let ids = members.sorted { ($0.title ?? "") < ($1.title ?? "") }.map(\.id)
                    DispatchQueue.main.async { self.stackedIDs.wrappedValue = ids }
                } else {
                    // A numbered dot: zoom in until its courses come apart.
                    mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                }
                return
            }
            guard let course = annotation as? CourseAnnotation, pickedID.wrappedValue != course.id else { return }
            DispatchQueue.main.async { self.pickedID.wrappedValue = course.id }
        }

        /// The most meters between any course and the first one.
        static func spread(of members: [CourseAnnotation]) -> CLLocationDistance {
            guard let first = members.first else { return 0 }
            let start = MKMapPoint(first.coordinate)
            return members.map { start.distance(to: MKMapPoint($0.coordinate)) }.max() ?? 0
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            guard let course = annotation as? CourseAnnotation else { return }
            DispatchQueue.main.async {
                // Tapping the map away from a dot puts the course card away.
                if self.pickedID.wrappedValue == course.id, mapView.selectedAnnotations.isEmpty {
                    self.pickedID.wrappedValue = nil
                }
            }
        }
    }
}

/// One course on the map.
final class CourseAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init?(_ entry: CourseIndex.Entry) {
        guard let lat = entry.lat, let lng = entry.lng else { return nil }
        id = entry.id
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        title = entry.name
        subtitle = entry.town
    }
}

/// A course's dot: red, edged in paper so it shows on any part of the map.
/// The picked course's dot grows and gets an ink ring.
final class CourseDotView: MKAnnotationView {
    static let reuseID = "course-dot"
    private static let size: CGFloat = 16

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "course"
        collisionMode = .circle
        displayPriority = .defaultHigh
        canShowCallout = false
        selectedZPriority = .max
        frame = CGRect(x: 0, y: 0, width: 30, height: 30)  // a bigger target than the dot
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var annotation: MKAnnotation? {
        didSet {
            clusteringIdentifier = "course"
            if let course = annotation as? CourseAnnotation {
                accessibilityLabel = [course.title, course.subtitle].compactMap { $0 }.joined(separator: ", ")
                accessibilityIdentifier = "map-course-\(course.id)"
            }
            setNeedsDisplay()
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        setNeedsDisplay()
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let size = isSelected ? Self.size * 1.5 : Self.size
        let dot = CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        let ring = UIBezierPath(ovalIn: dot)
        UIColor(Book.paper).setFill()
        ring.fill()
        let inner = UIBezierPath(ovalIn: dot.insetBy(dx: 2.5, dy: 2.5))
        UIColor(Book.red).setFill()
        inner.fill()
        UIColor(isSelected ? Book.ink : Book.ink.opacity(0.6)).setStroke()
        ring.lineWidth = isSelected ? 2 : 0.75
        ring.stroke()
        if isSelected {
            UIColor(Book.paper).setFill()
            UIBezierPath(ovalIn: CGRect(x: bounds.midX - 2.5, y: bounds.midY - 2.5, width: 5, height: 5)).fill()
        }
    }
}

/// Courses too close together to tap apart at this zoom: one dot with how many.
final class CourseClusterView: MKAnnotationView {
    static let reuseID = "course-cluster"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        displayPriority = .defaultHigh
        canShowCallout = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "map-cluster"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var annotation: MKAnnotation? {
        didSet {
            let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
            let side: CGFloat = count < 10 ? 30 : count < 100 ? 38 : 46
            frame = CGRect(x: 0, y: 0, width: side, height: side)
            accessibilityLabel = "\(count) courses. Tap to see them."
            setNeedsDisplay()
        }
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
        let circle = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        UIColor(Book.paper).setFill()
        circle.fill()
        UIColor(Book.red).setFill()
        UIBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4)).fill()
        UIColor(Book.ink.opacity(0.6)).setStroke()
        circle.lineWidth = 0.75
        circle.stroke()

        let font = UIFont(name: "CourierNewPS-BoldMT", size: count < 100 ? 14 : 13) ?? .monospacedSystemFont(ofSize: 13, weight: .bold)
        let text = "\(count)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Book.paper)]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2), withAttributes: attributes)
    }
}
