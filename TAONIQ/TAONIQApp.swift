import SwiftUI

@main
struct TAONIQApp: App {
    @State private var store = FlowStore()

    var body: some Scene {
        WindowGroup {
            HomeView(store: store)
                .preferredColorScheme(.light)
        }
    }
}
