import AppKit
import Foundation
import SwiftUI

/// The app title, e.g. "Netsi Image (1.0.0)".
public enum AppTitle {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public static var title: String {
        "Netsi Image (\(version))"
    }
}

/// Applies the title to the app window, which is not the same as the scene title.
public struct WindowTitleModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.async {
                    for window in NSApp.windows {
                        window.title = AppTitle.title
                    }
                }
            }
    }
}
