//
//  PlannerApp.swift
//  Planner
//
//  Created by Pratham Shetty on 25/05/25.
//

import SwiftUI
import EventKit

@main
struct PlannerApp: App {
    @StateObject private var viewModel = PlannerViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
