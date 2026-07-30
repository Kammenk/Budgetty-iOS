//
//  EmojiCatalog.swift
//  Budgetty
//
//  The curated pool of emoji offered when a user picks an icon for a custom category — ~220 glyphs in
//  nine themed sections, each carrying search keywords. Ported 1:1 from Android's `EmojiCatalog.kt`
//  so both platforms share one vocabulary. Every glyph is a single code point (a few with VS-16),
//  Unicode ≤ 13.1, with no ZWJ / skin-tone / gender / profession sequences so they render
//  consistently. Kept plain (no SwiftUI) so it can be unit-tested off-screen.
//

import Foundation

enum EmojiCatalog {

    /// One pickable icon: the `emoji` and the keyword tokens it matches in search.
    struct Entry: Hashable { let emoji: String; let keywords: [String] }

    /// A titled group of icons, shown as a labelled section in the grid.
    struct Section: Hashable { let title: String; let entries: [Entry] }

    /// Splits "☕ coffee cafe …" into an `Entry` (glyph up to the first space, keyword tokens after).
    private static func entries(_ specs: [String]) -> [Entry] {
        specs.map { spec in
            guard let cut = spec.firstIndex(of: " ") else { return Entry(emoji: spec, keywords: []) }
            let emoji = String(spec[spec.startIndex..<cut])
            let keywords = spec[spec.index(after: cut)...].split(separator: " ").map(String.init)
            return Entry(emoji: emoji, keywords: keywords)
        }
    }

    static let sections: [Section] = [
        Section(title: "Food & Drink", entries: entries([
            "☕ coffee cafe espresso drink", "🍵 tea matcha drink", "🧃 juice carton drink",
            "🥤 soda drink cup takeaway", "🍺 beer pub bar drink", "🍷 wine bar drink",
            "🍔 burger fastfood takeout", "🍕 pizza takeout fastfood", "🌮 taco mexican takeout",
            "🍜 noodles ramen soup", "🍝 pasta spaghetti", "🍣 sushi japanese",
            "🥗 salad healthy lunch", "🍞 bread toast bakery", "🥖 baguette bread bakery",
            "🥐 croissant pastry bakery", "🧀 cheese dairy", "🥚 eggs dairy",
            "🍗 chicken meat poultry", "🥩 steak meat beef", "🐟 fish seafood",
            "🍎 apple fruit", "🍌 banana fruit", "🍇 grapes fruit", "🥑 avocado fruit",
            "🥕 carrot vegetable veg", "🥬 greens vegetable veg", "🍫 chocolate sweets candy",
            "🍪 cookie biscuit sweets", "🍰 cake dessert sweets", "🍦 icecream dessert",
            "🥫 canned tinned pantry", "🥜 nuts snacks", "🧂 salt spices pantry",
            "🧊 ice frozen", "🍼 baby formula bottle", "🍽️ dining restaurant eatout",
            "🍴 restaurant eatout cutlery",
        ])),
        Section(title: "Transport", entries: entries([
            "🚗 car auto vehicle drive", "🚕 taxi cab ride car", "🚌 bus transit commute",
            "🚈 metro subway train transit", "🚆 train rail commute", "🚐 van minibus car",
            "🚲 bike bicycle cycling", "🛵 scooter moped", "🏍️ motorcycle bike",
            "⛽ fuel petrol gas car", "🅿️ parking car garage", "🎫 ticket fare pass transit",
            "🛣️ toll road motorway car", "🚦 traffic commute", "🧳 luggage travel trip",
            "✈️ flight plane travel airfare", "🚢 ferry ship cruise", "⛵ boat sailing",
            "🚁 helicopter", "🚀 rocket", "🔧 repair service garage car",
        ])),
        Section(title: "Home", entries: entries([
            "🏠 home house rent", "🏡 house garden home", "🏘️ housing rent mortgage",
            "🔑 keys rent deposit", "🛋️ furniture sofa living", "🛏️ bed bedroom furniture",
            "🪑 chair furniture", "🚪 door repair", "🚿 shower water", "🛁 bath bathroom",
            "🚽 toilet plumbing", "🧹 cleaning broom chores", "🧺 laundry washing",
            "🧼 soap cleaning", "🧴 lotion toiletries", "🧽 sponge cleaning",
            "💡 light bulb electricity", "🔌 power plug electricity", "⚡ energy electric utility",
            "💧 water utility", "🔥 gas heating", "🔨 diy repair tools",
            "🛠️ tools maintenance diy", "🧰 toolbox repair",
        ])),
        Section(title: "Shopping", entries: entries([
            "🛒 groceries shopping cart", "🛍️ shopping bags retail", "🎁 gift present",
            "📦 parcel delivery package", "🏷️ sale price tag", "🧾 receipt bill",
            "💳 card payment", "👕 clothes tshirt apparel", "👗 dress clothes apparel",
            "👖 jeans clothes", "👟 shoes sneakers trainers", "👞 shoes formal",
            "👜 handbag bag", "🎒 backpack school bag", "🧢 cap hat", "🧦 socks",
            "🧥 coat jacket", "👔 shirt work formal", "🕶️ sunglasses",
            "👓 glasses eyewear optician", "💍 jewellery ring", "⌚ watch",
            "💄 makeup cosmetics beauty",
        ])),
        Section(title: "Health", entries: entries([
            "💊 pharmacy medicine pills", "🩺 doctor medical checkup", "🏥 hospital clinic medical",
            "🩹 plaster firstaid", "🦷 dentist teeth dental", "😷 mask illness",
            "🌡️ fever thermometer health", "🧘 yoga wellness gym studio",
            "🏋️ gym fitness workout weights", "🏃 running jogging fitness gym",
            "🚴 cycling spin fitness gym", "🏊 swimming pool gym", "⚽ football soccer sport",
            "🏀 basketball sport", "🎾 tennis sport", "🥊 boxing gym sport",
            "💇 haircut salon barber", "💅 nails manicure salon", "🧖 spa sauna wellness",
            "❤️ health wellbeing love",
        ])),
        Section(title: "Leisure & Hobbies", entries: entries([
            "🎬 cinema movies film", "🎧 music streaming podcast audio", "🎵 songs music",
            "🎸 guitar music lessons", "🎹 piano keyboard music", "🥁 drums music",
            "🎤 karaoke singing", "🎨 art painting hobby", "🎭 theatre show",
            "📚 books reading", "📖 reading book study", "🎮 games gaming console",
            "🕹️ arcade games", "🎲 boardgames dice", "♟️ chess games", "🎯 darts hobby",
            "🎳 bowling", "🎪 events circus", "🎟️ tickets events entertainment",
            "🏕️ camping outdoors", "🏖️ beach holiday vacation", "🎣 fishing hobby",
            "🧩 puzzle hobby", "📷 photography camera", "🎉 party celebration",
        ])),
        Section(title: "Money & Work", entries: entries([
            "💰 money savings cash", "💵 cash dollars money", "💶 euros cash money",
            "💷 pounds cash money", "🏦 bank banking", "📈 investments stocks growth",
            "📉 losses stocks", "📊 budget charts report", "💼 work business job",
            "📁 files admin", "📄 documents paperwork admin", "📎 office supplies stationery",
            "🖊️ pen stationery", "✏️ pencil school stationery", "💻 laptop computer tech",
            "🖥️ desktop computer tech", "📱 phone mobile bill", "🖨️ printer office",
            "📞 calls phone bill", "📧 email internet", "🗓️ subscription calendar plan",
            "⏰ alarm time", "🏢 office rent business", "🎓 education tuition school",
            "🔔 subscriptions alerts",
        ])),
        Section(title: "Animals & Nature", entries: entries([
            "🐕 dog pet puppy", "🐈 cat pet kitten", "🐾 pet paws animals", "🐦 bird pet",
            "🐠 fish aquarium pet", "🐹 hamster rodent pet", "🐰 rabbit bunny pet",
            "🐴 horse riding", "🌱 plants seedling garden", "🌳 tree garden outdoors",
            "🌵 cactus plant", "🌸 blossom flowers", "🌻 sunflower flowers", "🌹 rose flowers",
            "🌿 herbs plants", "🍀 luck clover", "☀️ sun summer weather", "🌧️ rain weather",
            "❄️ snow winter cold", "🌊 sea water waves", "⛰️ mountains hiking outdoors",
            "🌍 world travel global",
        ])),
        Section(title: "Symbols", entries: entries([
            "⭐ star favourite", "✨ sparkle special", "✅ done complete", "✔️ check tick",
            "❗ important urgent", "❓ unknown misc", "⚠️ warning", "🔒 locked secure",
            "📌 pinned", "📍 location place", "🔖 bookmark label", "♻️ recycling eco",
            "🚩 flag marker", "🆕 new", "🔄 recurring repeat subscription",
            "⏳ pending waiting", "🕐 time hourly", "➕ plus add", "🔵 blue circle dot",
            "🟣 purple circle dot", "🟢 green circle dot", "🟡 yellow circle dot",
            "🔴 red circle dot",
        ])),
    ]

    /// Every pickable emoji, in section/grid order — the pool `Categories.iconChoices` exposes.
    static let all: [String] = sections.flatMap { $0.entries.map(\.emoji) }

    /// Icons whose keywords match `query`, ranked exact-token-first. A glyph is an exact hit when one
    /// of its keyword tokens equals the query, a prefix hit when a token merely starts with it; exact
    /// hits win outright and prefix hits only show when there are none (so "car" surfaces the
    /// vehicles, not "carton"/"carrot"). Blank query → empty (the caller shows the sectioned grid).
    static func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var exact: [Entry] = []
        var prefix: [Entry] = []
        for section in sections {
            for entry in section.entries {
                if entry.keywords.contains(q) { exact.append(entry) }
                else if entry.keywords.contains(where: { $0.hasPrefix(q) }) { prefix.append(entry) }
            }
        }
        return exact.isEmpty ? prefix : exact
    }
}
