//
//  MemoryCapabilityUpdater.swift
//  GetMoreRam
//
//  Update a modern Apple Developer Services capability with actionable,
//  non-sensitive error reporting. This mirrors AltSign's v1 PATCH format.
//

import Foundation
import StosSign_API
import StosSign_Common

struct MemoryCapabilityUpdateError: LocalizedError {
    let httpStatus: Int?
    let message: String

    var errorDescription: String? {
        if let httpStatus {
            return "Increased Memory Limit request failed (HTTP \(httpStatus))."
        }
        return "Increased Memory Limit request failed."
    }

    var failureReason: String? { message }

    var recoverySuggestion: String? {
        switch httpStatus {
        case 401:
            return "Your Apple Developer session may have expired. Sign in again."
        case 403:
            return "Apple may not allow this capability for the selected team or App ID. Check the team and capability permissions."
        case 404:
            return "Apple did not recognize this App ID in the Developer Services endpoint."
        case 409:
            return "Apple rejected this capability update. Review the error details above; do not assume the entitlement was granted."
        case 429:
            return "Too many requests. Avoid repeated attempts and try again later."
        case let status? where (500...599).contains(status):
            return "Apple's developer service may be temporarily unavailable."
        default:
            return "The App ID is unchanged unless Apple accepts the request. Do not rely on the memory entitlement until it is present in the new provisioning profile."
        }
    }
}

enum MemoryCapabilityUpdater {
    static let capabilityID = "INCREASED_MEMORY_LIMIT"
    static let entitlementKey = "com.apple.developer.kernel.increased-memory-limit"

    static func enable(for appID: AppID, team: Team, session: AppleAPISession) async throws -> String {
        let url = AppleAPI.shared.v1URL
            .appendingPathComponent("bundleIds")
            .appendingPathComponent(appID.identifier)

        // Modern capability updates use this JSON:API bundleIds relationship,
        // not the legacy QH65B2 feature flags.
        let requestBody: [String: Any] = [
            "data": [
                "type": "bundleIds",
                "id": appID.identifier,
                "attributes": [
                    "name": appID.name,
                    "identifier": appID.bundleIdentifier,
                    "teamId": team.identifier,
                    "seedId": team.identifier,
                    "bundleType": "bundle",
                    "hasExclusiveManagedCapabilities": false
                ],
                "relationships": [
                    "bundleIdCapabilities": [
                        "data": [[
                            "type": "bundleIdCapabilities",
                            "attributes": [
                                "enabled": true,
                                "settings": []
                            ],
                            "relationships": [
                                "capability": [
                                    "data": [
                                        "type": "capabilities",
                                        "id": capabilityID
                                    ]
                                ]
                            ]
                        ]]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // StosSign's generic PATCH helper accepts any JSON but discards the
        // JSON:API errors array, reducing 4xx responses to AppleAPIError code 3.
        // AltSign uses application/vnd.api+json for BOTH of these headers.
        let anisette = session.anisetteData
        let headers: [String: String] = [
            "Content-Type": "application/vnd.api+json",
            "Accept": "application/vnd.api+json",
            "User-Agent": "Xcode",
            "Accept-Language": "en-us",
            "X-Apple-App-Info": "com.apple.gs.xcode.auth",
            "X-Xcode-Version": "27.0 (27A5218g)",
            "X-Apple-I-Identity-Id": session.dsid,
            "X-Apple-GS-Token": session.authToken,
            "X-Apple-I-MD-M": anisette.machineID,
            "X-Apple-I-MD": anisette.oneTimePassword,
            "X-Apple-I-MD-LU": anisette.localUserID,
            "X-Apple-I-MD-RINFO": String(anisette.routingInfo),
            "X-Mme-Device-Id": anisette.deviceUniqueIdentifier,
            "X-MMe-Client-Info": anisette.deviceDescription,
            "X-Apple-I-Client-Time": ISO8601DateFormatter().string(from: anisette.date),
            "X-Apple-Locale": anisette.locale.identifier,
            "X-Apple-I-Locale": anisette.locale.identifier,
            "X-Apple-I-TimeZone": anisette.timeZone.abbreviation() ?? "GMT"
        ]
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        // Never log request headers, tokens, or raw response bodies. Parse only
        // documented error fields returned by the developer service.
        let (body, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MemoryCapabilityUpdateError(httpStatus: nil, message: "No HTTP response from Apple Developer Services.")
        }

        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let appleErrors = json?["errors"] as? [[String: Any]] ?? []
        if !appleErrors.isEmpty {
            let messages = appleErrors.prefix(3).map { error -> String in
                let code = (error["code"] as? String) ?? (error["status"] as? String) ?? ""
                let title = error["title"] as? String ?? ""
                let detail = error["detail"] as? String ?? ""
                let text = [code, title, detail].filter { !$0.isEmpty }.joined(separator: ": ")
                return String(text.prefix(600))
            }
            throw MemoryCapabilityUpdateError(
                httpStatus: http.statusCode,
                message: messages.joined(separator: "\n")
            )
        }

        guard (200...299).contains(http.statusCode) else {
            throw MemoryCapabilityUpdateError(
                httpStatus: http.statusCode,
                message: json?["error"] as? String ?? "Apple rejected the capability update or returned a non-JSON error page."
            )
        }

        // Some valid endpoints return 204 without JSON. A 200 JSON:API
        // response should include the updated bundleId resource.
        if http.statusCode != 204 && json?["data"] as? [String: Any] == nil {
            throw MemoryCapabilityUpdateError(
                httpStatus: http.statusCode,
                message: "Apple returned success without a recognizable updated bundle ID. The capability change is unverified."
            )
        }

        return "Apple Developer Services accepted the capability update (HTTP \(http.statusCode)).\nRequested: \(capabilityID)\nThe actual entitlement is NOT verified yet. Re-sign and reinstall LiveContainer2 with a newly generated provisioning profile, then inspect that profile and the signed app for \(entitlementKey)."
    }
}
