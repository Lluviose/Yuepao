import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// 选择器给的视频文件：系统的临时文件用完就会被删，先挪到自己的临时目录
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let dest = MediaStore.shared.incomingURL(ext: received.file.pathExtension)
            do {
                try FileManager.default.moveItem(at: received.file, to: dest)
            } catch {
                try FileManager.default.copyItem(at: received.file, to: dest)
            }
            return PickedMovie(url: dest)
        }
    }
}

/// 从系统相册导入：照片保留原始编码（HEIC 就是 HEIC），视频拿原文件，
/// 实况照片把照片和配对视频都存下来。选择器要用 `preferredItemEncoding: .current`，否则系统可能会转码
enum MediaImporter {
    static let filter = PHPickerFilter.any(of: [.images, .videos])

    /// 导入一项，成功返回 id
    static func importItem(_ item: PhotosPickerItem) async -> String? {
        let types = item.supportedContentTypes
        let isImage = types.contains { $0.conforms(to: .image) }
        let isMovie = types.contains { $0.conforms(to: .movie) }
        if isMovie && !isImage {
            return await importMovie(item)
        }
        if let id = await importLive(item) {
            return id
        }
        return await importStill(item)
    }

    private static func importStill(_ item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return try? MediaStore.shared.importPhoto(data: data)
    }

    private static func importMovie(_ item: PhotosPickerItem) async -> String? {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        return try? await MediaStore.shared.importVideo(at: movie.url)
    }

    /// 实况：取出照片和配对视频的原始资源分别保存。取不到时返回 nil，按普通照片导入
    private static func importLive(_ item: PhotosPickerItem) async -> String? {
        guard let live = try? await item.loadTransferable(type: PHLivePhoto.self) else { return nil }
        let resources = PHAssetResource.assetResources(for: live)
        guard let photo = resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo }),
              let video = resources.first(where: { $0.type == .fullSizePairedVideo })
                ?? resources.first(where: { $0.type == .pairedVideo }) else { return nil }
        let store = MediaStore.shared
        let photoURL = store.incomingURL(ext: fileExtension(of: photo, fallback: "heic"))
        let videoURL = store.incomingURL(ext: fileExtension(of: video, fallback: "mov"))
        defer {
            try? FileManager.default.removeItem(at: photoURL)
            try? FileManager.default.removeItem(at: videoURL)
        }
        do {
            try await write(photo, to: photoURL)
            try await write(video, to: videoURL)
            return try await store.importLive(photoURL: photoURL, videoURL: videoURL)
        } catch {
            return nil
        }
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func fileExtension(of resource: PHAssetResource, fallback: String) -> String {
        let ext = (resource.originalFilename as NSString).pathExtension
        if !ext.isEmpty { return ext.lowercased() }
        return UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? fallback
    }
}

/// 导出：存回系统相册、分享原文件
enum MediaExporter {
    /// 存回系统相册。实况会以实况保存，照片视频都是原文件
    static func saveToLibrary(_ id: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaError.notAuthorized }
        let store = MediaStore.shared
        guard let info = store.info(id) else { throw MediaError.missing }
        let main = try store.plainFile(id)
        var pair: URL?
        if info.kind == .live {
            pair = try store.plainFile(id, part: .pair)
        }
        let kind = info.kind
        let pairURL = pair
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            switch kind {
            case .photo:
                request.addResource(with: .photo, fileURL: main, options: nil)
            case .video:
                request.addResource(with: .video, fileURL: main, options: nil)
            case .live:
                request.addResource(with: .photo, fileURL: main, options: nil)
                if let pairURL {
                    request.addResource(with: .pairedVideo, fileURL: pairURL, options: nil)
                }
            }
        }
    }

    /// 分享用的原文件（实况分享的是照片）
    static func shareURL(_ id: String) throws -> URL {
        try MediaStore.shared.plainFile(id)
    }
}
