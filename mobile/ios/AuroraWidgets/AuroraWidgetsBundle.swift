import SwiftUI
import WidgetKit

@main
struct AuroraWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        AuroraLiveActivity()
    }
}
