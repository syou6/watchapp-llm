import SwiftUI

@main
struct WatchVoiceApp: App {
    @State private var pipeline: ConversationPipeline
    @State private var connectivity: PhoneConnectivity

    init() {
        let pipeline = ConversationPipeline()
        _pipeline = State(initialValue: pipeline)
        _connectivity = State(initialValue: PhoneConnectivity(pipeline: pipeline))
    }

    var body: some Scene {
        WindowGroup {
            ReactionView(pipeline: pipeline, connectivity: connectivity)
        }
    }
}
