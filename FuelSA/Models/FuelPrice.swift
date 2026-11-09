import Foundation

struct FuelPrice: Identifiable, Codable {
    let id: UUID
    let type: String
    let priceCents: Double
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        type: String,
        priceCents: Double,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.priceCents = priceCents
        self.updatedAt = updatedAt
    }
}
