import AppKit
import Foundation

@MainActor
protocol FolderPicking {
    func chooseFolder(title: String) async -> URL?
}

@MainActor
struct NSOpenPanelFolderPicker: FolderPicking {
    func chooseFolder(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return await panel.begin() == .OK ? panel.url : nil
    }
}
