//
//  Categories.swift
//  Budgetty
//
//  The spending taxonomy, ported 1:1 from Android's category/Categories.kt — a two-level set where
//  BOTH levels are selectable (a top-level group, or a sub-category that belongs to one). Colors are
//  computed with the same farthest-point hue-sampling algorithm as Android, so the pie/tiles render
//  identical hues on both platforms.
//

import Foundation

enum Categories {
    /// A selectable category: a group (`parent == nil`) or a sub-category of `parent`.
    struct Predefined: Hashable {
        let name: String
        let emoji: String
        let colorArgb: Int
        let parent: String?
    }

    /// Fallback category used when none is chosen.
    static let defaultName = "Groceries"
    /// The catch-all a custom category's transactions fall back to when it is deleted.
    static let other = "Other"

    /// Custom-category caps: free tier vs. Premium.
    static let freeCustomLimit = 3
    static let maxCustomLimit = 10

    // MARK: - Raw definitions (name, emoji, parent), in display order

    private struct Def { let name: String; let emoji: String; let parent: String? }

    private static let defs: [Def] = [
        // 🧺 Groceries
        Def(name: "Groceries", emoji: "🧺", parent: nil),
        Def(name: "Bakery", emoji: "🥖", parent: "Groceries"),
        Def(name: "Dairy", emoji: "🧀", parent: "Groceries"),
        Def(name: "Meat & Poultry", emoji: "🍗", parent: "Groceries"),
        Def(name: "Fish & Seafood", emoji: "🐟", parent: "Groceries"),
        Def(name: "Fruits & Vegetables", emoji: "🥬", parent: "Groceries"),
        Def(name: "Snacks & Sweets", emoji: "🍫", parent: "Groceries"),
        Def(name: "Frozen Foods", emoji: "🧊", parent: "Groceries"),
        Def(name: "Nuts & Snacks", emoji: "🥜", parent: "Groceries"),
        Def(name: "Canned & Preserved", emoji: "🥫", parent: "Groceries"),
        Def(name: "Grains & Pasta", emoji: "🍝", parent: "Groceries"),
        Def(name: "Condiments & Sauces", emoji: "🧂", parent: "Groceries"),
        Def(name: "Beverages", emoji: "🥤", parent: "Groceries"),
        // 🏠 Household & Personal
        Def(name: "Household & Personal", emoji: "🏠", parent: nil),
        Def(name: "Household Cleaning", emoji: "🧼", parent: "Household & Personal"),
        Def(name: "Personal Care", emoji: "🧴", parent: "Household & Personal"),
        Def(name: "Beauty", emoji: "💇", parent: "Household & Personal"),
        Def(name: "Baby Products", emoji: "🍼", parent: "Household & Personal"),
        Def(name: "Pet Supplies", emoji: "🐾", parent: "Household & Personal"),
        Def(name: "Paper Products", emoji: "📄", parent: "Household & Personal"),
        Def(name: "Kitchen Supplies", emoji: "🍽️", parent: "Household & Personal"),
        // ❤️ Health & Wellness
        Def(name: "Health & Wellness", emoji: "❤️", parent: nil),
        Def(name: "Health & Pharmacy", emoji: "💊", parent: "Health & Wellness"),
        Def(name: "Medical", emoji: "🏥", parent: "Health & Wellness"),
        Def(name: "Sports & Fitness", emoji: "🏋️", parent: "Health & Wellness"),
        // 🍽️ Dining & Entertainment
        Def(name: "Dining & Entertainment", emoji: "🍽️", parent: nil),
        Def(name: "Restaurant & Dining", emoji: "🍴", parent: "Dining & Entertainment"),
        Def(name: "Entertainment", emoji: "🎟️", parent: "Dining & Entertainment"),
        // 🛍️ Shopping & Lifestyle
        Def(name: "Shopping & Lifestyle", emoji: "🛍️", parent: nil),
        Def(name: "Clothing & Accessories", emoji: "👗", parent: "Shopping & Lifestyle"),
        Def(name: "Electronics", emoji: "🔌", parent: "Shopping & Lifestyle"),
        Def(name: "Garden & Plants", emoji: "🌱", parent: "Shopping & Lifestyle"),
        Def(name: "Home Improvement", emoji: "🛠️", parent: "Shopping & Lifestyle"),
        Def(name: "Tobacco & Alcohol", emoji: "🍷", parent: "Shopping & Lifestyle"),
        // 🚗 Transportation
        Def(name: "Transportation", emoji: "🚗", parent: nil),
        Def(name: "Fuel", emoji: "⛽", parent: "Transportation"),
        Def(name: "Car Maintenance", emoji: "🔧", parent: "Transportation"),
        // 📋 Services & Subscriptions
        Def(name: "Services & Subscriptions", emoji: "📋", parent: nil),
        Def(name: "Subscriptions & Services", emoji: "🔔", parent: "Services & Subscriptions"),
        Def(name: "Education", emoji: "📚", parent: "Services & Subscriptions"),
        Def(name: "Travel & Accommodation", emoji: "✈️", parent: "Services & Subscriptions"),
        Def(name: "Insurance & Utilities", emoji: "⚡", parent: "Services & Subscriptions"),
        Def(name: "Rent", emoji: "🏘️", parent: "Services & Subscriptions"),
        Def(name: "Office & Work Supplies", emoji: "📎", parent: "Services & Subscriptions"),
        Def(name: "Gifts & Charitable Donations", emoji: "🎁", parent: "Services & Subscriptions"),
        // 📦 Catch-all
        Def(name: "Other", emoji: "📦", parent: nil),
    ]

    // MARK: - Colors

    private static let baseSat: Float = 0.53
    private static let baseVal: Float = 0.75

    /// Exact top-level group colors (from the design's Insights pie), in insertion order — the order
    /// also seeds the sub-category hue spread, so keep it identical to Android.
    private static let groupColorOrdered: [(String, Int)] = [
        ("Groceries", 0xFF4FA85A),
        ("Household & Personal", 0xFFC77DB0),
        ("Health & Wellness", 0xFF5BB6A6),
        ("Dining & Entertainment", 0xFFE0795B),
        ("Shopping & Lifestyle", 0xFFAE72CC),
        ("Transportation", 0xFFD08A4A),
        ("Services & Subscriptions", 0xFF588AC7),
    ]
    private static let groupColor: [String: Int] = Dictionary(uniqueKeysWithValues: groupColorOrdered)

    /// Neutral grey for the catch-all "Other".
    private static let otherColor = 0xFF9A93A6

    /// Every selectable category (groups + sub-categories + Other), in display order, with colors.
    /// Sub-category hues are placed at the point farthest from all already-assigned hues (farthest-
    /// point sampling seeded from the pinned group hues) so no two collide.
    static let predefined: [Predefined] = {
        var usedHues: [Float] = groupColorOrdered.map { hueOf($0.1) }
        var subHue: [String: Float] = [:]

        for d in defs where d.parent != nil {
            var bestHue: Float = 0
            var bestDist: Float = -1
            var h: Float = 0
            while h < 360 {
                let dist = usedHues.map { hueDistance(h, $0) }.min() ?? 0
                if dist > bestDist {
                    bestDist = dist
                    bestHue = h
                }
                h += 0.5
            }
            subHue[d.name] = bestHue
            usedHues.append(bestHue)
        }

        return defs.map { d in
            let color: Int
            if d.name == "Other" {
                color = otherColor
            } else if d.parent == nil {
                color = groupColor[d.name]!
            } else {
                color = hsvColor(subHue[d.name]!)
            }
            return Predefined(name: d.name, emoji: d.emoji, colorArgb: color, parent: d.parent)
        }
    }()

    /// Top-level categories (the groups + Other), in display order.
    static let groups: [Predefined] = predefined.filter { $0.parent == nil }

    /// Sub-categories belonging to `group`, in display order.
    static func children(of group: String) -> [Predefined] {
        predefined.filter { $0.parent == group }
    }

    /// The top-level group `name` rolls up into (case-insensitive); groups / Other / custom / unknown
    /// return `name` unchanged. Collapses the Insights breakdown down to top-level groups.
    static func groupOf(_ name: String) -> String {
        predefined.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.parent ?? name
    }

    /// True if `name` is a built-in category (group, sub-category, or "Other"), case-insensitive.
    static func isPredefined(_ name: String) -> Bool {
        predefined.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func find(_ name: String) -> Predefined? {
        predefined.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The canonical packed color for `name` (predefined; falls back to the default custom color).
    /// Custom categories resolve from the DB's `Category` rows at the call site.
    static func color(for name: String) -> Int { find(name)?.colorArgb ?? defaultColor }

    /// The emoji for `name` (predefined; generic receipt glyph as fallback).
    static func emoji(for name: String) -> String { find(name)?.emoji ?? "🧾" }

    /// Colors offered when creating a custom category — the app's own muted family.
    static let palette: [Int] = [
        0xFFC65B5B, 0xFF4FA85A, 0xFF8B6CC4, 0xFFC8A44A, 0xFF4AA3C7, 0xFFC05E8A,
        0xFF73B647, 0xFF6B7BC4, 0xFFC8793A, 0xFF5BB6A6, 0xFFA060C0, 0xFFC77DB0,
    ]
    static var defaultColor: Int { palette.first! }

    /// Emoji offered in the custom-category icon grid — the distinct predefined icons.
    static let iconChoices: [String] = {
        var seen = Set<String>()
        return predefined.map(\.emoji).filter { seen.insert($0).inserted }
    }()

    // MARK: - Color math (pure, mirrors Android)

    /// Shortest distance in degrees (0...180) between two hues around the wheel.
    private static func hueDistance(_ a: Float, _ b: Float) -> Float {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// Hue in degrees (0...360) of a packed ARGB color; neutral (zero-chroma) returns 0.
    private static func hueOf(_ argb: Int) -> Float {
        let r = Float((argb >> 16) & 0xFF) / 255
        let g = Float((argb >> 8) & 0xFF) / 255
        let b = Float(argb & 0xFF) / 255
        let maxV = max(r, g, b)
        let chroma = maxV - min(r, g, b)
        if chroma == 0 { return 0 }
        let h: Float
        if maxV == r {
            h = ((g - b) / chroma).truncatingRemainder(dividingBy: 6)
        } else if maxV == g {
            h = (b - r) / chroma + 2
        } else {
            h = (r - g) / chroma + 4
        }
        return ((h * 60).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// HSV → packed 0xFFRRGGBB (fully opaque), muted saturation + medium value.
    private static func hsvColor(_ hue: Float, s: Float = baseSat, v: Float = baseVal) -> Int {
        let hn = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = v * s
        let x = c * (1 - abs((hn / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r1, g1, b1): (Float, Float, Float)
        switch Int(hn / 60) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let r = Int(((r1 + m) * 255)).clamped(0, 255)
        let g = Int(((g1 + m) * 255)).clamped(0, 255)
        let b = Int(((b1 + m) * 255)).clamped(0, 255)
        return (0xFF << 24) | (r << 16) | (g << 8) | b
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.max(lo, Swift.min(hi, self)) }
}
