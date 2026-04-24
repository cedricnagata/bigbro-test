import SwiftUI
import UIKit

@main
struct bigbro_testApp: App {
    @StateObject private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    viewModel.disconnect()
                }
        }
    }
}
