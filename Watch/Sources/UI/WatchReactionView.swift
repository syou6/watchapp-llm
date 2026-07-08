import SwiftUI

struct WatchReactionView: View {
    @State private var link = WatchConnectivity()

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                Text(link.reaction.isEmpty
                     ? (link.isListening ? "聞いてます…" : "タップして開始")
                     : link.reaction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.1), value: link.reaction)
            }

            if !link.status.isEmpty {
                Text(link.status).font(.caption2).foregroundStyle(.secondary)
            }

            Button(action: { link.toggleListening() }) {
                Image(systemName: link.isListening ? "stop.fill" : "mic.fill")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .tint(link.isListening ? .red : .accentColor)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 6)
    }
}

#Preview {
    WatchReactionView()
}
