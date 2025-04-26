//
//  FirestoreService.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 12/27/24.
//

@preconcurrency import Firebase
import Dependencies

public protocol FirestoreServiceProtocol {
    static func request<T>(_ endpoint: FirestoreEndpoint) async throws -> T where T: FirestoreIdentifiable
    static func request<T>(_ endpoint: FirestoreEndpoint, lastQuerySnapshot: @escaping (QuerySnapshot) -> Void) async throws -> [T] where T: FirestoreIdentifiable
    static func request(_ endpoint: FirestoreEndpoint) async throws -> Void
    static func listener<T>(_ endpoint: FirestoreEndpoint) -> AsyncThrowingStream<[T], Error> where T: FirestoreIdentifiable
}

public extension FirestoreServiceProtocol {
    func request<T>(_ endpoint: FirestoreEndpoint) async throws -> [T] where T: FirestoreIdentifiable {
        try await Self.request(endpoint, lastQuerySnapshot: { _ in })
    }
}

public protocol FirestoreServiceActorProtocol {
    func request<T>(_ endpoint: FirestoreEndpoint) async throws -> T where T: FirestoreIdentifiable
    func request<T>(_ endpoint: FirestoreEndpoint, pageSize: Int) async throws -> [T] where T: FirestoreIdentifiable
    func request(_ endpoint: FirestoreEndpoint) async throws -> Void
    func listener<T>(_ endpoint: FirestoreEndpoint/*, pageSize: Int*/) async -> AsyncThrowingStream<[T], Error> where T: FirestoreIdentifiable
}

public extension FirestoreServiceActorProtocol {
    func request<T>(_ endpoint: FirestoreEndpoint) async throws -> [T] where T: FirestoreIdentifiable {
        try await self.request(endpoint, pageSize: Int.max)
    }
}

public actor NewFirestoreService: FirestoreServiceActorProtocol {
    
    var cursor: DocumentSnapshot?
    
    public nonisolated func request<T>(_ endpoint: FirestoreEndpoint) async throws -> T where T: FirestoreIdentifiable {
        guard let ref = endpoint.path as? DocumentReference else {
            throw FirestoreServiceError.documentNotFound
        }
        switch endpoint.method {
        case .get:
            guard let documentSnapshot = try? await ref.getDocument() else {
                throw FirestoreServiceError.invalidPath
            }

            guard let documentData = documentSnapshot.data() else {
                throw FirestoreServiceError.parseError
            }

            let singleResponse = try FirestoreParser.parse(documentData, type: T.self)
            return singleResponse
        default:
            throw FirestoreServiceError.invalidRequest
        }

    }

    public func request<T: Sendable>(
        _ endpoint: any FirestoreEndpoint,
        pageSize: Int
    ) async throws -> [T] where T : FirestoreIdentifiable {
        guard var ref = endpoint.path as? Query else {
            throw FirestoreServiceError.collectionNotFound
        }
        
        switch endpoint.method {
        case .get:
//            if let cursor = self.cursor {
//                ref = ref.start(afterDocument: cursor)
//            }
//            
            let querySnapshot = try await ref.getDocuments()
//            
//            guard !querySnapshot.isEmpty else {
//                // There are no results and so there can be no more results to paginate; nil the cursor.
//                self.cursor = nil
//                return []
//            }
//            
//            // Before parsing the snapshot, manage the cursor.
//            if querySnapshot.count < pageSize {
//                // This snapshot is smaller than a page size and so there can be no more results to paginate; nil the cursor.
//                self.cursor = nil
//                print("Hi BD! We are inside of niling the cursor")
//            }
//            else {
//                // This snapshot is a full page size and so there could potentially be more results to paginate; set the cursor.
//                self.cursor = querySnapshot.documents.last
//                print("Hi BD! We are inside of setting the cursor to the last document.")
//            }
            
            
            var response: [T] = []
            for document in querySnapshot.documents {
                let data = try FirestoreParser.parse(document.data(), type: T.self)
                response.append(data)
                if document === querySnapshot.documents.last {
                    print("Hi BD! This is the current cursor value: \(response.last?.id)")
                }
            }
//            self.cursor = querySnapshot.documents.last
//            print("Hi BD! Response has been fetched and cursor is now set to \(response.last?.id)")
            
            return response
        case .post, .put, .delete:
            throw FirestoreServiceError.operationNotSupported
        }
    }
    
    public nonisolated func request(_ endpoint: FirestoreEndpoint) async throws -> Void {
        guard let ref = endpoint.path as? DocumentReference else {
            throw FirestoreServiceError.documentNotFound
        }
        switch endpoint.method {
        case .get:
            throw FirestoreServiceError.invalidRequest
        case .post(var model):
            model.id = ref.documentID
            try await ref.setData(model.asDictionary())
        case .put(let dict):
            try await ref.updateData(dict)
            break
        case .delete:
            try await ref.delete()
        }
    }
    
    public nonisolated func listener<T>(_ endpoint: any FirestoreEndpoint) async -> AsyncThrowingStream<[T], any Error> where T : FirestoreIdentifiable {
        AsyncThrowingStream { continuation in
            guard var ref = endpoint.path as? Query else {
                continuation.finish(throwing: FirestoreServiceError.documentNotFound)
                return
            }
            
//            if let cursor = self.cursor {
//                ref = ref.start(afterDocument: cursor)
//            }
            
            let listener = ref.addSnapshotListener { querySnapshot, error in
//                guard let querySnapshot else {
//                    if let error = error {
//                        print(error)
//                    }
//                    return
//                }
//                
//                guard !querySnapshot.isEmpty else {
//                    // There are no results and so there can be no more results to paginate; nil the cursor.
//                    self.cursor = nil
//                    return
//                }
//                
//                // Before parsing the snapshot, manage the cursor.
//                if querySnapshot.count < pageSize {
//                    // This snapshot is smaller than a page size and so there can be no more results to paginate; nil the cursor.
//                    self.cursor = nil
//                } else {
//                    // This snapshot is a full page size and so there could potentially be more results to paginate; set the cursor.
//                    self.cursor = querySnapshot.documents.last
//                }
                
                if let error {
                    continuation.finish(throwing: error)
                } else{
                    continuation.yield(querySnapshot?.documents
                        .compactMap {
                            do {
                                return try $0.data(as: T.self)
                            } catch {
                                return nil
                            }
                        } ?? [])
                }
            }
            
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }
}

public final class FirestoreService: FirestoreServiceProtocol {

    private init() {}
    
    public static func listener<T>(_ endpoint: any FirestoreEndpoint) -> AsyncThrowingStream<[T], any Error> where T : FirestoreIdentifiable {
        AsyncThrowingStream { continuation in
            guard let ref = endpoint.path as? Query else {
                continuation.finish(throwing: FirestoreServiceError.documentNotFound)
                return
            }
            
            let listener = ref.addSnapshotListener { querySnapshot, error in
                if let error {
                    continuation.finish(throwing: error)
                } else{
                    continuation.yield(querySnapshot?.documents
                        .compactMap {
                            do {
                                return try $0.data(as: T.self)
                            } catch {
                                return nil
                            }
                        } ?? [])
                }
            }
            
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    public static func request<T>(_ endpoint: FirestoreEndpoint) async throws -> T where T: FirestoreIdentifiable {
        guard let ref = endpoint.path as? DocumentReference else {
            throw FirestoreServiceError.documentNotFound
        }
        switch endpoint.method {
        case .get:
            guard let documentSnapshot = try? await ref.getDocument() else {
                throw FirestoreServiceError.invalidPath
            }

            guard let documentData = documentSnapshot.data() else {
                throw FirestoreServiceError.parseError
            }

            let singleResponse = try FirestoreParser.parse(documentData, type: T.self)
            return singleResponse
        default:
            throw FirestoreServiceError.invalidRequest
        }

    }

    public static func request<T>(_ endpoint: FirestoreEndpoint, lastQuerySnapshot: @escaping (QuerySnapshot) -> Void = { _ in }) async throws -> [T] where T: FirestoreIdentifiable {
        guard let ref = endpoint.path as? Query else {
            throw FirestoreServiceError.collectionNotFound
        }
        switch endpoint.method {
        case .get:
            let querySnapshot = try await ref.getDocuments()
            var response: [T] = []
            for document in querySnapshot.documents {
                let data = try FirestoreParser.parse(document.data(), type: T.self)
                response.append(data)
            }
            lastQuerySnapshot(querySnapshot)
            return response
        case .post, .put, .delete:
            throw FirestoreServiceError.operationNotSupported
        }
    }

    public static func request(_ endpoint: FirestoreEndpoint) async throws -> Void {
        guard let ref = endpoint.path as? DocumentReference else {
            throw FirestoreServiceError.documentNotFound
        }
        switch endpoint.method {
        case .get:
            throw FirestoreServiceError.invalidRequest
        case .post(var model):
            model.id = ref.documentID
            try await ref.setData(model.asDictionary())
        case .put(let dict):
            try await ref.updateData(dict)
            break
        case .delete:
            try await ref.delete()
        }
    }
}

public enum FirestoreServiceError: Error {
    case documentNotFound
    case invalidPath
    case parseError
    case invalidRequest
    case collectionNotFound
    case operationNotSupported
}


extension NewFirestoreService: DependencyKey {
    public static var liveValue: NewFirestoreService {
        return NewFirestoreService()
    }
}

extension DependencyValues: Sendable {
    public var firestoreService: NewFirestoreService {
        get { self[NewFirestoreService.self] }
        set { self[NewFirestoreService.self] = newValue }
    }
}
