//
//  Dimens.swift
//  Budgetty
//
//  Central spacing / sizing tokens, ported from the Android app's ui/theme/Dimens.kt.
//  Read these instead of scattering literal point values through the views, so phone and
//  tablet (iPad) can be tuned in one place later.
//

import CoreGraphics

enum Dimens {
    // Spacing scale
    static let spaceXXS: CGFloat = 2
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 20
    static let spaceXXL: CGFloat = 24
    static let spaceXXXL: CGFloat = 32

    // Screen edges
    static let screenPadding: CGFloat = 16

    // Corners
    static let cornerS: CGFloat = 8
    static let cornerM: CGFloat = 12
    static let cornerL: CGFloat = 16
    static let cornerXL: CGFloat = 24
    static let cardCorner: CGFloat = 20

    // Standard control sizes (Android standardized action buttons to 56dp height)
    static let buttonHeight: CGFloat = 56
    static let categoryTile: CGFloat = 30
    static let avatar: CGFloat = 40
    static let iconM: CGFloat = 24
}
