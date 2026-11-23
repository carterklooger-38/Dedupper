import SwiftUI

@main
struct DedupperApp: App {
    @State private var model = AppModel.live()
    @State private var quickLook = QuickLookCoordinator()
    private let picker = NSOpenPanelFolderPicker()

    var body: some Scene {
        WindowGroup {
            RootView(model: model, picker: picker, quickLook: quickLook)
                .frame(idealWidth: 1_240, idealHeight: 780)
        }
        .defaultSize(width: 1_240, height: 780)
    }
}
