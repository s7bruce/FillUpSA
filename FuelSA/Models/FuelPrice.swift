import Foundation

struct FuelPrice: Codable, Hashable {
    let type: String          // e.g. "ULP 91"
    let priceCents: Double    // cents per litre
}
