//
//  StationListView.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import SwiftUI

struct StationListView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Views/StationListView.swift
        List(app.stations, id: \.id) { s in
            StationRow(station: s, preferredFuel: app.preferredFuel)
        }
        .refreshable { await app.refresh() }
        .listStyle(.plain)
    }
}
