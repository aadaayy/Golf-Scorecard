import SwiftUI
import UIKit

extension Book {
    /// Bars and switches drawn by UIKit (navigation bars, tab bars, segmented
    /// switches) in paper and ink. Called once at launch.
    static func styleSystemControls() {
        let ink = UIColor(Book.ink)
        let paper = UIColor(Book.paper)
        let titleFont = UIFont(name: "CourierNewPS-BoldMT", size: 19) ?? .monospacedSystemFont(ofSize: 17, weight: .bold)
        let largeFont = UIFont(name: "CourierNewPS-BoldMT", size: 32) ?? .monospacedSystemFont(ofSize: 30, weight: .bold)

        // Navigation bars: clear over the paper at the top of a page, then solid
        // paper with a thin rule once content scrolls under. (An opaque bar at
        // the top hid the big page titles under a tab bar.)
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = paper
        bar.shadowColor = UIColor(Book.rule)
        bar.titleTextAttributes = [.font: titleFont, .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: largeFont, .foregroundColor: ink]
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = bar.titleTextAttributes
        edge.largeTitleTextAttributes = bar.largeTitleTextAttributes
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = edge
        UINavigationBar.appearance().compactScrollEdgeAppearance = edge
        UINavigationBar.appearance().tintColor = ink

        // Tab bars: paper, with the picked tab in ink.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = paper
        tabs.shadowColor = UIColor(Book.rule)
        let tabFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(Book.pencil)
            item.normal.titleTextAttributes = [.font: tabFont, .foregroundColor: UIColor(Book.pencil)]
            item.selected.iconColor = ink
            item.selected.titleTextAttributes = [.font: tabFont, .foregroundColor: ink]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = ink

        // Segmented switches (Front 9 / Back 9, Hole / Nine, tees): the picked
        // side on a lighter sheet in bold ink, readable in the page and in the
        // glass toolbar alike.
        let segments = UISegmentedControl.appearance()
        segments.selectedSegmentTintColor = UIColor(Book.page)
        segments.backgroundColor = UIColor(Book.shade)
        segments.setTitleTextAttributes([
            .foregroundColor: ink,
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold),
        ], for: .selected)
        segments.setTitleTextAttributes([
            .foregroundColor: UIColor(Book.pencil),
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium),
        ], for: .normal)

        UISwitch.appearance().onTintColor = ink
    }
}

extension View {
    /// The whole app's look: ink, monospaced type, paper, always light like a printed page.
    func bookStyle() -> some View {
        self
            .tint(Book.ink)
            .foregroundStyle(Book.ink)
            .fontDesign(.monospaced)
            .preferredColorScheme(.light)
    }

    /// A list or form printed on the paper instead of the system's grey.
    func bookList() -> some View {
        scrollContentBackground(.hidden)
            .paperBackground()
    }

    /// A list row on a lighter sheet, or marked when it's the one picked.
    func bookRow(marked: Bool = false) -> some View {
        listRowBackground(marked ? Book.markedRow : Book.page)
    }
}

extension Book {
    /// A picked row: the page with a wash of red.
    static let markedRow = Color(red: 0.961, green: 0.894, blue: 0.851)
}
