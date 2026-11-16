import Foundation

struct HostingGroup: Decodable, Identifiable {
    let id: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let description: String?
        let location: String?
    }
}
