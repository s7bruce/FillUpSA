//
//  StationRow.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import SwiftUI

struct StationRow: View {
    let station: Station
    let preferredFuel: String

    private func priceText() -> String {
        if let value = station.priceForSelection(preferredFuel), value.isFinite {
            return String(format: "%.1f\u{00A2}", value)
        }
        return "\u{2014}"
    }

    private func timeAgo(_ date: Date) -> String {
        let mins = max(1, Int(Date().timeIntervalSince(date) / 60))
        return "\(mins)m ago"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name).font(.headline)
                Text(station.brand).font(.caption).foregroundStyle(.secondary)
                Text("Updated \(timeAgo(station.lastUpdated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(priceText())
                .font(.title3).monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}

