import SwiftUI

@main
struct KomawariApp: App {
    @State private var store = TimetableStore()

    var body: some Scene {
        WindowGroup {
            WeekScreen()
                .environment(store)
        }
    }
}
