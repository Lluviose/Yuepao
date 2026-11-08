import UIKit
import CryptoKit
import Security

/// 照片加密存储：AES-GCM 加密后放在 App 沙盒里，密钥在钥匙串，不进系统相册。
final class PhotoStore {
    static let shared = PhotoStore()

    private let fm = FileManager.default
    private let cache = NSCache<NSString, UIImage>()
    private lazy var key: SymmetricKey = KeychainKey.loadOrCreate()

    let directory: URL

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Photos", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
        cache.countLimit = 300
    }

    private func url(for id: String) -> URL {
        directory.appendingPathComponent(id + ".enc")
    }

    // MARK: Save

    /// 从相册选择器拿到的原始数据
    func save(data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return save(image: image)
    }

    func save(image: UIImage) -> String? {
        let resized = image.resized(maxDimension: 2048)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let id = UUID().uuidString
        return writeEncrypted(jpeg, id: id) ? id : nil
    }

    /// 备份恢复时写入
    @discardableResult
    func importRaw(_ jpeg: Data, id: String) -> Bool {
        writeEncrypted(jpeg, id: id)
    }

    private func writeEncrypted(_ plain: Data, id: String) -> Bool {
        do {
            let sealed = try AES.GCM.seal(plain, using: key)
            guard let combined = sealed.combined else { return false }
            try combined.write(to: url(for: id), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    // MARK: Read

    /// 解密后的 JPEG 数据
    func rawData(_ id: String) -> Data? {
        guard let encrypted = try? Data(contentsOf: url(for: id)),
              let box = try? AES.GCM.SealedBox(combined: encrypted),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return plain
    }

    func image(_ id: String) -> UIImage? {
        guard let data = rawData(id) else { return nil }
        return UIImage(data: data)
    }

    func thumbnail(_ id: String, size: CGFloat = 240) -> UIImage? {
        let cacheKey = "\(id)-\(Int(size))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let full = image(id) else { return nil }
        let thumb = full.resized(maxDimension: size)
        cache.setObject(thumb, forKey: cacheKey)
        return thumb
    }

    // MARK: Delete

    func delete(_ id: String) {
        try? fm.removeItem(at: url(for: id))
        cache.removeAllObjects()
    }

    func delete(_ ids: [String]) {
        ids.forEach { try? fm.removeItem(at: url(for: $0)) }
        cache.removeAllObjects()
    }

    func deleteAll() {
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        cache.removeAllObjects()
    }

    func allIDs() -> [String] {
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "enc" }.map { $0.deletingPathExtension().lastPathComponent }
    }
}

enum KeychainKey {
    private static let service = "com.lluviose.yuepao.photo-key"

    static func loadOrCreate() -> SymmetricKey {
        if let data = load() { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        store(data)
        return key
    }

    private static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { return nil }
        return data
    }

    private static func store(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
