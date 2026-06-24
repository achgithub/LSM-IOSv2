//
//  LSMApp.swift
//  LSM
//

import SwiftUI
import SwiftData

@main
struct LSMApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [Game.self, Player.self, Round.self, Pick.self, RosterMember.self, PlayerGroup.self])
    }
}
