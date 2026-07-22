//
//  AccentTests.swift
//  BudgettyTests
//
//  The accent themes re-colour two surfaces that carry **white text** — the hero card gradient and
//  the primary-action capsule. Copying the mockup's HSB numbers to another hue would have shipped a
//  Sage hero at roughly 1.6:1 contrast, because green at a given "brightness" is far lighter to the
//  eye than violet. `AccentOption` therefore derives those colours by matching the reference
//  *luminance*; these tests are what stop that guarantee from silently rotting.
//

import Testing
@testable import Budgetty

struct AccentTests {
    /// Contrast floor for the white label on the hero card / CTA capsule. Both draw large, semibold
    /// text, where WCAG asks 3:1. The shipped violet's worst case is its lightest gradient stop
    /// (#9A6FE0, ≈3.7:1); because the derivation matches luminance, every other accent lands on the
    /// same number — this floor catches the day someone "adjusts" a hex by eye and drops below it.
    private static let minimumContrast = 3.0

    @Test(arguments: AccentOption.allCases)
    func heroGradientKeepsWhiteTextReadable(accent: AccentOption) {
        // The lightest stop is the worst case for white text.
        for reference in [0x5E_4CAB, 0x7B_5AC8, 0x9A_6FE0] {
            let derived = accent.rgbMatchingLuminance(of: reference)
            #expect(AccentOption.contrastWithWhite(derived) >= Self.minimumContrast)
        }
    }

    @Test(arguments: AccentOption.allCases)
    func ctaKeepsWhiteTextReadable(accent: AccentOption) {
        for reference in [0x6B_50A8, 0x7E_60E0] {
            let derived = accent.rgbMatchingLuminance(of: reference)
            #expect(AccentOption.contrastWithWhite(derived) >= Self.minimumContrast)
        }
    }

    /// The derivation is only honest if it actually lands on the reference luminance — otherwise
    /// "same readability as violet" is a claim, not a fact.
    @Test(arguments: AccentOption.allCases)
    func derivedColoursMatchTheReferenceLuminance(accent: AccentOption) {
        for reference in [0x5E_4CAB, 0x9A_6FE0, 0x7E_60E0] {
            let target = AccentOption.luminance(ofRGB: reference)
            let derived = AccentOption.luminance(of: accent.rgbMatchingLuminance(of: reference))
            #expect(abs(derived - target) < 0.01)
        }
    }

    /// Each accent keeps its own hue — a derivation bug that collapsed them all to one colour would
    /// still pass the contrast tests above.
    @Test func accentsAreDistinctHues() {
        let hues = AccentOption.allCases.map { AccentOption.hue(of: $0.hexes.light) }
        for (i, a) in hues.enumerated() {
            for b in hues[(i + 1)...] {
                #expect(abs(a - b) > 0.05)
            }
        }
    }

    /// Violet is the mockup's own palette and must stay byte-exact, derivation or not.
    @Test func violetIsUnchangedFromTheMockup() {
        #expect(AccentOption.violet.hexes.light == 0x6B_50A8)
        #expect(AccentOption.violet.hexes.dark == 0xC4_AEFF)
    }
}
