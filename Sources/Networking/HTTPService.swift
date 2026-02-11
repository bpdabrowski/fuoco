//
//  HTTPService.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 2/11/26.
//

import Foundation
import Dependencies

public protocol HTTPServiceProtocol {
    func request<T: Decodable>(_ endpoint: HTTPEndpoint) async throws -> T
    func request<T: Decodable>(_ endpoint: HTTPEndpoint) async throws -> [T]
}

public final class HTTPService: HTTPServiceProtocol, Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    public func request<T: Decodable>(_ endpoint: HTTPEndpoint) async throws -> T {
        let request = endpoint.urlRequest
        
        print("🌐 [HTTPService] Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPServiceError.invalidResponse
        }
        
        print("📡 [HTTPService] Response: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPServiceError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            print("❌ [HTTPService] Decode error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 [HTTPService] Response data: \(jsonString)")
            }
            throw HTTPServiceError.decodingError(error)
        }
    }
    
    public func request<T: Decodable>(_ endpoint: HTTPEndpoint) async throws -> [T] {
        let request = endpoint.urlRequest
        
        print("🌐 [HTTPService] Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPServiceError.invalidResponse
        }
        
        print("📡 [HTTPService] Response: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPServiceError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoded = try decoder.decode([T].self, from: data)
            return decoded
        } catch {
            print("❌ [HTTPService] Decode error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 [HTTPService] Response data: \(jsonString)")
            }
            throw HTTPServiceError.decodingError(error)
        }
    }
}

public enum HTTPServiceError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error with status code: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

extension HTTPService: DependencyKey {
    public static var liveValue: HTTPService {
        return HTTPService()
    }
}

extension DependencyValues {
    public var httpService: HTTPService {
        get { self[HTTPService.self] }
        set { self[HTTPService.self] = newValue }
    }
}
