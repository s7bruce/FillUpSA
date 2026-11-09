//
//  ApiModels.swift
//  FillUpSA
//

import Foundation

// MARK: - PRICE RESPONSE

struct ApiSitePricesResponse: Decodable {
    let SitePrices: [ApiSitePrice]
}

struct ApiSitePrice: Decodable {
    let SiteId: Int
    let FuelId: Int
    let CollectionMethod: String
    let TransactionDateUtc: String
    let Price: Double
}

// MARK: - BRAND RESPONSE

struct ApiBrandsResponse: Decodable {
    let Brands: [ApiBrand]
}

struct ApiBrand: Decodable {
    let BrandId: Int
    let Name: String
}

// MARK: - SITE DETAILS RESPONSE (SHORT KEYS)

struct ApiSiteDetailsResponse: Decodable {
    let S: [ApiSite]
}

struct ApiSite: Decodable {
    let S: Int          // SiteId
    let A: String?      // Address
    let N: String?      // Name
    let B: Int?         // Brand ID (not always meaningful)
    let P: String?      // Postcode
    let G1: Int?        // Region 1
    let G2: Int?
    let G3: Int?
    let G4: Int?
    let G5: Int?
    let Lat: Double?    // Latitude
    let Lng: Double?    // Longitude
    let M: String?      // Last modified timestamp
    let MO: String?
    let MC: String?
    let TO: String?
    let TC: String?
    let WO: String?
    let WC: String?
    let THO: String?
    let THC: String?
    let FO: String?
    let FC: String?
    let SO: String?
    let SC: String?
    let SUO: String?
    let SUC: String?
}
