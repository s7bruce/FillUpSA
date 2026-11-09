//
//  CarPlaySceneDelegate.swift
//  
//
//  Created by Samuel Bruce on 9/10/2025.
//

import UIKit
import CarPlay
import MapKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    var coordinator: CarPlayCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        self.coordinator = CarPlayCoordinator(interfaceController: interfaceController)
        coordinator?.start()
    }

    private func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.coordinator = nil
    }
}
