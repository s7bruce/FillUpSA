//
//  ContentView.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Fuel", selection: $app.preferredFuel) {
                    ForEach(["91","E10","95","98","Diesel","LPG"], id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                StationMapView()
                    .frame(height: 260)

                StationListView()
            }
            .navigationTitle("Fill Up SA")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if app.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await app.refresh() }
                        } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
    }
}
