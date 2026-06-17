import WidgetKit
import SwiftUI

/// Widget extension entry point. A bundle so we can add more widgets later
/// (e.g. a multi-window medium layout) without another target.
///
/// TODO(xcode): WidgetKit extensions build only in Xcode.
@main
struct TallyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TallyWidget()
    }
}
