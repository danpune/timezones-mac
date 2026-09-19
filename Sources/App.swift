import SwiftUI

@main
struct TimeZonesApp: App {
    @NSApplicationDelegateAdaptor(StatusController.self) private var controller
    var body: some Scene { Settings { EmptyView() } }
}
