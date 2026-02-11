//
//  StorageClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 4/5/25.
//

import Dependencies
@preconcurrency import FirebaseStorage
import SwiftUI
import AVFoundation

public struct UploadProgress: Sendable {
    public let fractionCompleted: Double
    public let totalBytes: Int64
    public let completedBytes: Int64
    
    public init(fractionCompleted: Double, totalBytes: Int64, completedBytes: Int64) {
        self.fractionCompleted = fractionCompleted
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
    }
}

public struct StorageClient: Sendable {
    static let storage = Storage.storage()
    public var upload: @Sendable (_ image: UIImage) async -> URL?
    public var uploadVideo: @Sendable (_ videoURL: URL, _ onProgress: @Sendable @escaping (UploadProgress) -> Void) async -> URL?
}

extension StorageClient: DependencyKey {
    public static var liveValue: StorageClient {
        StorageClient(
            upload: { image in
                let storageRef = Self.storage.reference().child("user_images/\(UUID()).jpg")
                let data = image.jpegData(compressionQuality: 0.75)
                
                let metadata = StorageMetadata()
                metadata.contentType = "image/jpg"
                
                guard let data = data else {
                    return nil
                }

                do {
                    let _ = try await storageRef.putDataAsync(data, metadata: metadata)
                    return try await storageRef.downloadURL()
                } catch {
                    return nil
                }
            },
            uploadVideo: { videoURL, onProgress in
                do {
                    let compressedURL = try await compressVideo(videoURL)
                    let storageRef = Self.storage.reference().child("user_videos/\(UUID()).mp4")
                    
                    let metadata = StorageMetadata()
                    metadata.contentType = "video/mp4"
                    
                    let uploadTask = storageRef.putFile(from: compressedURL, metadata: metadata)
                    
                    let progressObserver = uploadTask.observe(.progress) { snapshot in
                        guard let progress = snapshot.progress else { return }
                        let uploadProgress = UploadProgress(
                            fractionCompleted: progress.fractionCompleted,
                            totalBytes: progress.totalUnitCount,
                            completedBytes: progress.completedUnitCount
                        )
                        onProgress(uploadProgress)
                    }
                    
                    defer {
                        uploadTask.removeObserver(withHandle: progressObserver)
                        try? FileManager.default.removeItem(at: compressedURL)
                    }
                    
                    let _ = try await uploadTask
                    return try await storageRef.downloadURL()
                } catch {
                    return nil
                }
            }
        )
    }
}

extension DependencyValues: Sendable {
    public var storageClient: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}



private func compressVideo(_ inputURL: URL) async throws -> URL {
    let asset = AVURLAsset(url: inputURL)
    
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
        throw NSError(domain: "StorageClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
    }
    
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")
    
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    
    await exportSession.export()
    
    guard exportSession.status == .completed else {
        throw exportSession.error ?? NSError(domain: "StorageClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Video compression failed"])
    }
    
    return outputURL
}

extension UIImage {
    func aspectFittedToHeight(_ newHeight: CGFloat) -> UIImage {
        let scale = newHeight / self.size.height
        let newWidth = self.size.width * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
