//
//  pintuApp.swift
//  pintu
//
//

import SwiftUI

@main
struct pintuApp: App {
    @StateObject private var store = CollageStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
