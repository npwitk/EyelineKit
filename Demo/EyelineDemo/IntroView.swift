import SwiftUI

/// The "before you start" screen of Bank of Duoland, a pretend bank.
struct IntroView: View {
    var onStart: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Bank of Duoland")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Bank of Duoland")
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Face check")
                        .font(.largeTitle.bold())
                    Text("Show the vault guards it's really you.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    Row(symbol: "sunglasses", text: "Take off your hat and sunglasses.")
                    Row(symbol: "sun.max", text: "Find some light.")
                    Row(symbol: "iphone.gen3", text: "Close your iPhone and use the outer screen.")
                    Row(symbol: "eye", text: "Look at the camera. Instructions appear right beside it.")
                }
                
                Text("Bank of Duoland is pretend. Your face never leaves this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaBar(edge: .bottom) {
            Button(action: onStart) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: 520)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}

private struct Row: View {
    var symbol: String
    var text: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Duoland.green)
                .frame(width: 44, height: 44)
                .background(Duoland.green.opacity(0.1), in: .circle)
            Text(text)
        }
    }
}
