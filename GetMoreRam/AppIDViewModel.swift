//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AppIDModel : ObservableObject, Hashable {
    static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool {
        return lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    var appID: AppID
    @Published var bundleID: String
    @Published var result: String = ""
    
    init(appID: AppID) {
        self.appID = appID
        bundleID = appID.bundleIdentifier
    }
    
    func addIncreasedMemory() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        // StosSign's generic updateAppID helper hides JSON:API errors (including
        // permission/restriction details) behind AppleAPIError code 3. Use a
        // capability-specific request that reports Apple's actual response.
        await MainActor.run {
            result = "Submitting Increased Memory Limit capability request..."
        }
        do {
            let message = try await MemoryCapabilityUpdater.enable(
                for: appID, team: team, session: session
            )
            await MainActor.run {
                result = message
            }
        } catch {
            await MainActor.run {
                result = "The capability request failed. No memory entitlement has been verified.\n" + error.detailedDescription
            }
            throw error
        }
    }
    
}

class AppIDViewModel : ObservableObject {
    @Published var appIDs : [AppIDModel] = []
    
    func fetchAppIDs() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }
        
        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        await MainActor.run {
            appIDs.removeAll()
            for id in ids {
                appIDs.append(AppIDModel(appID: id))
            }
        }
    }
}
