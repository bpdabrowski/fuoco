//
//  StorageClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 4/5/25.
//

import Dependencies
@preconcurrency import FirebaseStorage
import SwiftUI

public struct StorageClient: Sendable {
    static let storage = Storage.storage()
    public var upload: @Sendable (_ image: UIImage) async -> URL?
}

extension StorageClient: DependencyKey {
    public static var liveValue: StorageClient {
        StorageClient(upload: { image in
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
        })
    }
}

extension DependencyValues: Sendable {
    public var storageClient: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
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
