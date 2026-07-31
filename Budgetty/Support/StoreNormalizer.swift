//
//  StoreNormalizer.swift
//  Budgetty
//
//  Collapses raw receipt store names to a single canonical brand (Android's StoreNormalizer). The
//  same chain prints under different branch/legal names — "Kaufland Lyulin" and "КАУФЛАНД БЪЛГАРИЯ
//  ЕООД" are both Kaufland — so subscription detection (and any store grouping) would otherwise see
//  one merchant as several. Unrecognised names fall through trimmed + whitespace-collapsed.
//

import Foundation

enum StoreNormalizer {

    private struct Brand { let canonical: String; let aliases: [String] }

    // Aliases are lowercase. A single-word alias matches a whole token only (so "dm" can't hit inside
    // another word); an alias containing a space or hyphen is matched as a substring.
    private static let brands: [Brand] = [
        Brand(canonical: "Kaufland", aliases: ["kaufland", "кауфланд", "каулланд"]),
        Brand(canonical: "Lidl", aliases: ["lidl", "лидл"]),
        Brand(canonical: "Billa", aliases: ["billa", "била"]),
        Brand(canonical: "Fantastico", aliases: ["fantastico", "фантастико"]),
        Brand(canonical: "T-Market", aliases: ["t-market", "t market", "тмаркет", "т маркет"]),
        Brand(canonical: "Metro", aliases: ["metro", "метро"]),
        Brand(canonical: "Praktiker", aliases: ["praktiker", "практикер"]),
        Brand(canonical: "Technopolis", aliases: ["technopolis", "технополис"]),
        Brand(canonical: "Technomarket", aliases: ["technomarket", "техномаркет"]),
        Brand(canonical: "Lilly", aliases: ["lilly", "лили"]),
        Brand(canonical: "dm", aliases: ["dm", "дм"]),
        Brand(canonical: "OMV", aliases: ["omv"]),
        Brand(canonical: "Shell", aliases: ["shell", "шел"]),
        Brand(canonical: "Lukoil", aliases: ["lukoil", "лукойл"]),
    ]

    /// The canonical brand for `raw`, or `raw` trimmed / space-collapsed when no brand matches.
    static func normalize(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if cleaned.isEmpty { return cleaned }
        let lower = cleaned.lowercased()
        let tokens = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for brand in brands {
            let matched = brand.aliases.contains { alias in
                if alias.contains(" ") || alias.contains("-") { return lower.contains(alias) }
                return tokens.contains(alias)
            }
            if matched { return brand.canonical }
        }
        return cleaned
    }
}
