//
//  StationMapView.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import SwiftUI
import MapKit

struct StationMapView: View {
    @EnvironmentObject var app: AppState
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -34.9285, longitude: 138.6007), // Adelaide CBD
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )

    var body: some View {
        Map(position: .constant(.region(region))) {
            ForEach(app.stations, id: \.id) { s in
                Annotation(s.name, coordinate: s.coordinate) {
                    ZStack {
                        Circle().frame(width: 28, height: 28).foregroundStyle(.thinMaterial)
                        Image(systemName: "fuelpump.fill")
                    }
                }
            }
        }
        .onChange(of: app.stations) { _ in
            if let first = app.stations.first {
                region.center = first.coordinate
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top)
    }
}
