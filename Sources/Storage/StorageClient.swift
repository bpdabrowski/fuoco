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
    public var uploadVideo: @Sendable (_ videoURL: URL, _ onProcessingComplete: @Sendable @escaping () -> Void, _ onProcessingProgress: @Sendable @escaping (Double) -> Void, _ onProgress: @Sendable @escaping (UploadProgress) -> Void) async -> URL?
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
            uploadVideo: { videoURL, onProcessingComplete, onProcessingProgress, onProgress in
                do {
                    let compressedURL = try await compressAndCropVideo(videoURL, onProgress: onProcessingProgress)
                    onProcessingComplete()
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



private func compressAndCropVideo(_ inputURL: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
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

    // Cap at 720p portrait; don't upscale if the source is already smaller.
    let scaleFactor = min(720 / cropWidth, 1280 / cropHeight, 1.0)
    let renderWidth = (cropWidth * scaleFactor / 2).rounded(.down) * 2
    let renderHeight = (cropHeight * scaleFactor / 2).rounded(.down) * 2
    let renderSize = CGSize(width: renderWidth, height: renderHeight)

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

    // Reader: decompress source frames applying the crop/orientation composition.
    let reader = try AVAssetReader(asset: asset)
    let readerVideoOutput = AVAssetReaderVideoCompositionOutput(
        videoTracks: [videoTrack],
        videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
    )
    readerVideoOutput.videoComposition = videoComposition
    readerVideoOutput.alwaysCopiesSampleData = false
    reader.add(readerVideoOutput)

    // Writer: encode with HEVC at 2 Mbps (~5 MB per 20 seconds).
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mp4")

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.hevc,
        AVVideoWidthKey: Int(renderSize.width),
        AVVideoHeightKey: Int(renderSize.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
    ])
    writerVideoInput.expectsMediaDataInRealTime = false
    writer.add(writerVideoInput)

    // Pass through audio re-encoded as AAC 128kbps.
    var writerAudioInput: AVAssetWriterInput?
    var readerAudioOutput: AVAssetReaderTrackOutput?
    if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM)
        ])
        reader.add(audioOutput)
        readerAudioOutput = audioOutput

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)
        writerAudioInput = audioInput
    }

    return try await withCheckedThrowingContinuation { continuation in
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let finishGroup = DispatchGroup()

        let totalSeconds = duration.seconds
        var lastReportedProgress: Double = 0

        finishGroup.enter()
        writerVideoInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.fuoco.video.write")) {
            while writerVideoInput.isReadyForMoreMediaData {
                if let sample = readerVideoOutput.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let progress = min(pts / totalSeconds, 1.0)
                    if progress - lastReportedProgress >= 0.01 {
                        lastReportedProgress = progress
                        onProgress(progress)
                    }
                    writerVideoInput.append(sample)
                } else {
                    writerVideoInput.markAsFinished()
                    finishGroup.leave()
                    return
                }
            }
        }

        if let writerAudioInput, let readerAudioOutput {
            finishGroup.enter()
            writerAudioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.fuoco.audio.write")) {
                while writerAudioInput.isReadyForMoreMediaData {
                    if let sample = readerAudioOutput.copyNextSampleBuffer() {
                        writerAudioInput.append(sample)
                    } else {
                        writerAudioInput.markAsFinished()
                        finishGroup.leave()
                        return
                    }
                }
            }
        }

        finishGroup.notify(queue: .global()) {
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: writer.error ?? NSError(
                        domain: "StorageClient",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Video compression failed"]
                    ))
                }
            }
        }
    }
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
