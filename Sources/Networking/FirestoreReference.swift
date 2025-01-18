//
//  FirestoreReference.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 12/27/24.
//

import Firebase

public protocol FirestoreReference { }

extension DocumentReference: FirestoreReference { }
extension CollectionReference: FirestoreReference { }
extension Query: FirestoreReference { }

public protocol FirestoreIdentifiable: Codable, Identifiable {
    var id: String { get set }
}

public typealias Dictionary = [String: Any]

extension Encodable {

    func asDictionary() -> Dictionary {
        guard let data = try? JSONEncoder().encode(self) else {
            return [:]
        }
        guard let dictionary = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? Dictionary else {
            return [:]
        }
        return dictionary
    }
}
