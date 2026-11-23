import AppKit
import Foundation
@preconcurrency import QuickLookUI

@MainActor
final class QuickLookCoordinator: NSObject {
    private var urls: [URL] = []

    func show(urls: [URL], selectedURL: URL) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = urls.firstIndex(of: selectedURL) ?? 0
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
        urls = []
    }

}

extension QuickLookCoordinator: @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> any QLPreviewItem {
        urls[index] as NSURL
    }
}
