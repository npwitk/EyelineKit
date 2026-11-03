import SwiftUI

@main
struct EyelineDemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Duoland.green)
        }
    }
}

struct RootView: View {
    @State private var checking = UserDefaults.standard.bool(forKey: "startCheck")

    var body: some View {
        if checking {
            CheckView(onClose: { checking = false })
        } else {
            IntroView(onStart: { checking = true })
        }
    }
}
