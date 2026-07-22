//
//  Legal.swift
//  Budgetty
//
//  The legal and support destinations, in one place because two screens need the same ones: Support
//  & About lists them, and the paywall is *required* to carry them (App Review 3.1.2 wants Terms of
//  Use and a privacy policy on the subscription screen itself, not just buried in settings).
//

import Foundation

enum Legal {
    /// The hosted privacy policy — the same document Android links to (`URL_PRIVACY` in
    /// AccountScreen.kt) and the one both store listings point at. Section 1(f) is what discloses
    /// crash reporting, so this link is part of the Crashlytics disclosure chain.
    static let privacyPolicy = URL(string: "https://budgetty-96a3d.web.app/")!

    /// Apple's standard EULA. Budgetty ships no terms document of its own, and this is the agreement
    /// that already governs its subscriptions by default — linking it is the honest answer, and it's
    /// what satisfies 3.1.2. If a custom EULA is ever written, this is the only place to change.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Same inbox Android mails (`SUPPORT_EMAIL`).
    static let supportEmail = "kamskstudio@gmail.com"

    /// One neutral subject for every kind of message. Deliberate: the row it opens covers problems,
    /// feature ideas and general contact alike (Android made the same call — see PARITY.md §4a), so a
    /// subject like "Bug report" would misfile two thirds of what arrives. English on both platforms;
    /// Android hardcodes it too, and a localized subject would just make triage harder.
    static var supportMail: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Budgetty feedback")]
        return components.url ?? URL(string: "mailto:\(supportEmail)")!
    }
}
