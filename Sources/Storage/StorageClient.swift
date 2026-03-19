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
                    let compressedURL = try await compressAndCropVideo(videoURL)
                    let storageRef = Self.storage.reference().child("user_videos/\(UUID()).mp4")
                    
                    let metadata = StorageMetadata()
                    metadata.contentType = "video/mp4"
                    
                    let uploadTask = storageRef.putFile(from: compressedURL, metadata: metadata)
                    
                    defer {
                        try? FileManager.default.removeItem(at: compressedURL)
                    }
                    
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        uploadTask.observe(.progress) { snapshot in
                            guard let progress = snapshot.progress else { return }
                            onProgress(UploadProgress(
                                fractionCompleted: progress.fractionCompleted,
                                totalBytes: progress.totalUnitCount,
                                completedBytes: progress.completedUnitCount
                            ))
                        }
                        
                        uploadTask.observe(.success) { _ in
                            uploadTask.removeAllObservers()
                            continuation.resume()
                        }
                        
                        uploadTask.observe(.failure) { snapshot in
                            uploadTask.removeAllObservers()
                            let error = snapshot.error ?? NSError(
                                domain: "StorageClient",
                                code: -4,
                                userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
                            )
                            continuation.resume(throwing: error)
                        }
                    }
                    
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



private func compressAndCropVideo(_ inputURL: URL) async throws -> URL {
    let asset = AVURLAsset(url: inputURL)
    let duration = try await asset.load(.duration)

    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(domain: "StorageClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)

    // Determine display size and normalize the transform so the display origin sits at (0,0).
    let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    let displayWidth = abs(transformedRect.width)
    let displayHeight = abs(transformedRect.height)
    var normalizedTransform = preferredTransform
    normalizedTransform.tx -= transformedRect.minX
    normalizedTransform.ty -= transformedRect.minY

    // Compute a center-crop rect in display space that achieves a 9:16 aspect ratio.
    let targetAspect: CGFloat = 9.0 / 16.0
    let displayAspect = displayWidth / displayHeight
    var cropOriginX: CGFloat = 0
    var cropOriginY: CGFloat = 0
    var cropWidth = displayWidth
    var cropHeight = displayHeight

    if abs(displayAspect - targetAspect) > 0.01 {
        if displayAspect > targetAspect {
            cropWidth = displayHeight * targetAspect
            cropOriginX = (displayWidth - cropWidth) / 2
        } else {
            cropHeight = displayWidth / targetAspect
            cropOriginY = (displayHeight - cropHeight) / 2
        }
    }

    let renderSize = CGSize(width: 1080, height: 1920)
    let scaleX = renderSize.width / cropWidth
    let scaleY = renderSize.height / cropHeight

    // Final transform: normalize orientation → translate to crop origin → scale to render size.
    let finalTransform = normalizedTransform
        .concatenating(CGAffineTransform(translationX: -cropOriginX, y: -cropOriginY))
        .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    layerInstruction.setTransform(finalTransform, at: .zero)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.instructions = [instruction]
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.renderSize = renderSize

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
        throw NSError(domain: "StorageClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
    }

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.videoComposition = videoComposition

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
