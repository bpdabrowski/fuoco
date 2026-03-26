//
//  FirestoreParser.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 12/27/24.
//

import Foundation
import Firebase

struct FirestoreParser {
    static func parse<T: Decodable>(_ documentData: [String: Any], type: T.Type) throws -> T {
        do {
            let sanitized = sanitize(documentData)
            let jsonData = try JSONSerialization.data(withJSONObject: sanitized, options: [])
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: jsonData)
        } catch {
            print("🚨 [FirestoreParser] Decode FAILED for \(T.self): \(error)")
            if let jsonData = try? JSONSerialization.data(withJSONObject: sanitize(documentData), options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🚨 [FirestoreParser] Raw JSON:\n\(jsonString)")
            }
            throw FirestoreServiceError.parseError
        }
    }

    private static func sanitize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { sanitize($0) }
        } else if let array = value as? [Any] {
            return array.map { sanitize($0) }
        } else if let geoPoint = value as? GeoPoint {
            return ["latitude": geoPoint.latitude, "longitude": geoPoint.longitude]
        } else if let timestamp = value as? Timestamp {
            return timestamp.dateValue().timeIntervalSince1970
        } else {
            return value
        }
    }
}
