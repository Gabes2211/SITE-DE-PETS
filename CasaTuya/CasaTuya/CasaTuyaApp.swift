import SwiftUI

@main
struct CasaTuyaApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
