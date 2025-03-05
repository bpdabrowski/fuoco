//
//  FirestoreEndpoint.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 12/27/24.
//

import FirebaseFirestore

public protocol FirestoreEndpoint {
    var path: FirestoreReference { get }
    var method: FirestoreMethod { get }
    var firestore: Firestore { get }
}

public extension FirestoreEndpoint {
    var firestore: Firestore {
        Firestore.firestore()
    }
}

public enum FirestoreMethod {
    case get
    case post(any FirestoreIdentifiable)
    case put([String: Any])
    case delete
}
