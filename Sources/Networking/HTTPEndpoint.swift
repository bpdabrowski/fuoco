//
//  HTTPEndpoint.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 2/11/26.
//

import Foundation

public protocol HTTPEndpoint: Sendable {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryParameters: [String: String] { get }
}

public extension HTTPEndpoint {
    var headers: [String: String] {
        ["Content-Type": "application/json"]
    }
    
    var queryParameters: [String: String] {
        [:]
    }
    
    var urlRequest: URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        
        if !queryParameters.isEmpty {
            components.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        return request
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
