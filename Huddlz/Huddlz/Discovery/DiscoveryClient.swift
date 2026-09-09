import Foundation

struct DiscoveryPage {
    let huddlz: [Huddl]
    let next: URL?
}

struct DiscoveryClient {
    private let baseURL: URL
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)

    init(
        baseURL: URL = URL(string: "https://huddlz.com")!,
        fetch: ((URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.baseURL = baseURL
        if let fetch {
            self.fetch = fetch
        } else {
            #if DEBUG
            if let service = UITestHTTPService.shared {
                self.fetch = { try await service.respond(to: $0) }
                return
            }
            #endif
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration)
            self.fetch = { try await session.data(for: $0) }
        }
    }

    func search(_ query: DiscoveryQuery) async throws -> DiscoveryPage {
        var components = URLComponents(url: baseURL.appending(path: "api/json/huddlz"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "date_filter", value: query.dates.rawValue),
            URLQueryItem(name: "search_time_zone", value: query.place?.timeZone ?? query.timeZone),
            URLQueryItem(name: "page[limit]", value: "20")
        ]
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { components.queryItems?.append(URLQueryItem(name: "query", value: text)) }
        if let type = query.eventType { components.queryItems?.append(URLQueryItem(name: "event_type", value: type.rawValue)) }
        if let place = query.place {
            components.queryItems?.append(contentsOf: [
                URLQueryItem(name: "search_latitude", value: String(place.latitude)),
                URLQueryItem(name: "search_longitude", value: String(place.longitude)),
                URLQueryItem(name: "distance_miles", value: String(query.distanceMiles))
            ])
        }
        return try await page(at: components.url!)
    }

    func page(at url: URL) async throws -> DiscoveryPage {
        guard url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.path == baseURL.appending(path: "api/json/huddlz").path,
              url.user == nil, url.password == nil else { throw DiscoveryError.invalidResponse }
        let document: PageDocument = try await get(url)
        return DiscoveryPage(huddlz: document.data, next: document.links?.next)
    }

    func detail(id: Huddl.ID) async throws -> Huddl {
        var components = URLComponents(url: baseURL.appending(path: "api/json/huddlz").appending(component: id), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "include", value: "group"),
            URLQueryItem(name: "fields[group]", value: "name")
        ]
        let document: DetailDocument = try await get(components.url!)
        var huddl = document.data
        if let host = huddl.relationships?.group?.data, host.type == "group" {
            huddl.hostName = document.included?.first { $0.type == host.type && $0.id == host.id }?.attributes?.name
        }
        return huddl
    }

    private func get<Value: Decodable>(_ url: URL) async throws -> Value {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw DiscoveryError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 { throw DiscoveryError.notFound }
            throw DiscoveryError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid event date"))
        }
        do { return try decoder.decode(Value.self, from: data) }
        catch { throw DiscoveryError.invalidResponse }
    }

    private struct PageDocument: Decodable {
        let data: [Huddl]
        let links: Links?
        struct Links: Decodable { let next: URL? }
    }
    private struct DetailDocument: Decodable {
        let data: Huddl
        let included: [IncludedResource]?

        struct IncludedResource: Decodable {
            let type: String
            let id: String
            let attributes: Attributes?
            struct Attributes: Decodable { let name: String? }
        }
    }
}

enum DiscoveryError: LocalizedError {
    case notFound, unavailable, invalidResponse

    var errorDescription: String? {
        switch self {
        case .notFound: "This huddl is no longer available."
        case .unavailable: "Huddlz couldn’t load right now. Please try again."
        case .invalidResponse: "We couldn’t read the huddl information. Please try again."
        }
    }
}
