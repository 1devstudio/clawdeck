import SwiftUI

/// The two supported inner-panel background modes.
enum InnerPanelBackgroundMode: String, CaseIterable, Identifiable {
    case solidColor = "solidColor"
    case unsplash = "unsplash"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solidColor: return "Solid Color"
        case .unsplash: return "Unsplash Image"
        }
    }
}

/// Snapshot of the user's background choice, propagated via SwiftUI environment.
struct InnerPanelBackgroundConfig: Equatable {
    let mode: InnerPanelBackgroundMode
    let colorHex: String
    let unsplashURL: String
    let unsplashPhotographer: String

    static let `default` = InnerPanelBackgroundConfig(
        mode: .solidColor,
        colorHex: "#1E1E2E",
        unsplashURL: "",
        unsplashPhotographer: ""
    )
}
