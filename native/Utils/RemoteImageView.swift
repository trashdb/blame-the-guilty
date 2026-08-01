import AppKit
import SwiftUI

/// Manual async image loader. AsyncImage is unreliable inside the menu-bar
/// popover (NSPanel/LSUIElement), so we fetch via URLSession + NSCache instead.
struct RemoteImageView: View {
    let url: URL?
    var placeholder: Image = Image(systemName: "person.circle.fill")

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                placeholder
            }
        }
        .onAppear { load() }
        .onChange(of: url) { load() }
    }

    private func load() {
        guard let url else { return }
        image = RemoteImageCache.shared.image(for: url)
        guard image == nil else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let loaded = NSImage(data: data) else { return }
            RemoteImageCache.shared.insert(loaded, for: url)
            DispatchQueue.main.async {
                image = loaded
            }
        }
        .resume()
    }
}

final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
