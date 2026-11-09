import Foundation

// MARK: - /Price/GetSitesPrices response (namespaced to avoid collisions)

enum ApiPriceModels {
    struct SitePricesResponse: Decodable {
        let sitePrices: [SitePrice]

        enum CodingKeys: String, CodingKey {
            case sitePrices = "SitePrices"
        }
    }

    struct SitePrice: Decodable {
        let siteId: Int
        let fuelId: Int
        let collectionMethod: String
        let transactionDateUtc: String
        let price: Double

        enum CodingKeys: String, CodingKey {
            case siteId = "SiteId"
            case fuelId = "FuelId"
            case collectionMethod = "CollectionMethod"
            case transactionDateUtc = "TransactionDateUtc"
            case price = "Price"
        }
    }
}


// MARK: - /Subscriber/GetFullSiteDetails response

struct ApiFullSiteDetailsResponse: Decodable {
    let sites: [ApiSiteDetail]

    enum CodingKeys: String, CodingKey {
        case sites = "S"
    }
}

struct ApiSiteDetail: Decodable {
    let id: Int
    let address: String
    let name: String
    let brandId: Int
    let postcode: String
    let geoRegionLevel1: Int
    let geoRegionLevel2: Int
    let geoRegionLevel3: Int
    let geoRegionLevel4: Int
    let latitude: Double
    let longitude: Double
    let modified: String
    let googlePlaceId: String
    let monOpen: String
    let monClose: String
    let tueOpen: String
    let tueClose: String
    let wedOpen: String
    let wedClose: String
    let thuOpen: String
    let thuClose: String
    let friOpen: String
    let friClose: String
    let satOpen: String
    let satClose: String
    let sunOpen: String
    let sunClose: String

    enum CodingKeys: String, CodingKey {
        case id = "S"
        case address = "A"
        case name = "N"
        case brandId = "B"
        case postcode = "P"
        case geoRegionLevel1 = "G1"
        case geoRegionLevel2 = "G2"
        case geoRegionLevel3 = "G3"
        case geoRegionLevel4 = "G4"
        case latitude = "Lat"
        case longitude = "Lng"
        case modified = "M"
        case googlePlaceId = "GPI"
        case monOpen = "MO"
        case monClose = "MC"
        case tueOpen = "TO"
        case tueClose = "TC"
        case wedOpen = "WO"
        case wedClose = "WC"
        case thuOpen = "THO"
        case thuClose = "THC"
        case friOpen = "FO"
        case friClose = "FC"
        case satOpen = "SO"
        case satClose = "SC"
        case sunOpen = "SUO"
        case sunClose = "SUC"
    }
}
