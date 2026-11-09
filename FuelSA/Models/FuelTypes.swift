func fuelName(for id: Int) -> String {
    switch id {
    case 2: return "91"
    case 3: return "Diesel"
    case 4: return "LPG"
    case 5: return "95"
    case 8: return "98"
    case 12: return "E10"
    case 14: return "Premium Diesel"
    case 19: return "E85"
    default: return "Unknown"
    }
}

func brandName(from id: Int?) -> String {
    guard let id = id else { return "" }
    switch id {
    case 169: return "OTR"
    case 2: return "Caltex"
    case 3421074: return "Silver's"
    default: return "Brand"
    }
}
