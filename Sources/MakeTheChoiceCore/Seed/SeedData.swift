import Foundation
import GRDB

/// Ships the initial category catalog and merchant→category mappings.
public enum SeedData {

    /// Inserts the 12 fixed categories.
    public static func installCategories(_ db: Database) throws {
        for category in AppCategory.allCases {
            try Category(category).insert(db)
        }
    }

    /// Inserts the seeded merchant→category mappings (source = .seed, unlocked).
    /// Keys are already in normalized form (`MerchantNormalizer.normalize`).
    public static func installMerchants(_ db: Database) throws {
        let now = Date()
        for (name, category) in merchantSeed {
            let normalized = MerchantNormalizer.normalize(name)
            guard !normalized.isEmpty else { continue }
            try Merchant(
                normalizedName: normalized,
                category: category,
                source: .seed,
                locked: false,
                updatedAt: now
            ).save(db)
        }
    }

    /// The seeded merchant catalog (~200 common merchants).
    public static let merchantSeed: [(String, AppCategory)] = {
        var m: [(String, AppCategory)] = []
        func add(_ category: AppCategory, _ names: [String]) {
            for n in names { m.append((n, category)) }
        }

        add(.food, [
            "mcdonalds", "starbucks", "subway", "chipotle", "kfc", "burger king",
            "taco bell", "dominos", "pizza hut", "wendys", "dunkin", "panera bread",
            "five guys", "shake shack", "popeyes", "chick fil a", "dairy queen",
            "whole foods", "trader joes", "safeway", "kroger", "publix", "aldi",
            "costco", "walmart grocery", "tesco", "sainsburys", "asda", "lidl",
            "morrisons", "waitrose", "carrefour", "doordash", "ubereats", "grubhub",
            "deliveroo", "just eat", "blue bottle", "pret a manger", "nandos",
            "greggs", "wagamama"
        ])

        add(.transport, [
            "uber", "lyft", "bolt", "shell", "chevron", "exxon", "bp", "texaco",
            "mobil", "arco", "valero", "76", "circle k", "speedway", "national rail",
            "trainline", "amtrak", "mta", "tfl", "transport for london", "bart",
            "caltrain", "parkmobile", "spothero", "zipcar", "hertz", "enterprise",
            "avis", "budget rent a car", "lime", "bird", "citi bike"
        ])

        add(.travel, [
            "delta", "united airlines", "american airlines", "southwest",
            "british airways", "lufthansa", "emirates", "ryanair", "easyjet",
            "jetblue", "alaska airlines", "klm", "air france", "qatar airways",
            "turkish airlines", "marriott", "hilton", "hyatt", "ihg", "airbnb",
            "booking com", "expedia", "hotels com", "vrbo", "kayak", "priceline",
            "trivago", "agoda", "travelocity"
        ])

        add(.subscriptions, [
            "netflix", "spotify", "hulu", "disney plus", "hbo max", "max",
            "youtube premium", "apple music", "apple tv", "amazon prime",
            "paramount plus", "peacock", "icloud", "google one", "dropbox",
            "microsoft 365", "adobe", "notion", "audible", "patreon", "substack",
            "nytimes", "the economist", "wall street journal", "medium",
            "linkedin premium", "github", "openai", "anthropic", "chatgpt"
        ])

        add(.enjoyment, [
            "steam", "playstation", "xbox", "nintendo", "epic games", "twitch",
            "amc theatres", "cinemark", "regal cinemas", "vue cinemas",
            "odeon", "ticketmaster", "stubhub", "eventbrite", "fandango",
            "live nation", "dave and busters", "topgolf", "bowlero", "spotify live"
        ])

        add(.health, [
            "cvs", "walgreens", "rite aid", "boots", "superdrug", "gnc",
            "planet fitness", "la fitness", "equinox", "anytime fitness",
            "puregym", "the gym group", "peloton", "classpass", "myfitnesspal",
            "quest diagnostics", "labcorp", "kaiser permanente", "teladoc",
            "zocdoc", "23andme", "headspace", "calm"
        ])

        add(.clothing, [
            "nike", "adidas", "puma", "under armour", "zara", "h m", "uniqlo",
            "gap", "old navy", "banana republic", "levis", "lululemon", "nordstrom",
            "macys", "asos", "primark", "next", "footlocker", "jd sports",
            "urban outfitters", "ralph lauren", "gucci", "the north face", "patagonia",
            "vans", "converse"
        ])

        add(.housing, [
            "ikea", "home depot", "lowes", "wayfair", "b q", "homebase",
            "bed bath beyond", "the container store", "ace hardware", "pg e",
            "con edison", "national grid", "duke energy", "british gas", "edf energy",
            "octopus energy", "thames water", "comcast", "xfinity", "spectrum",
            "verizon fios", "at t", "centurylink", "cox", "dyson"
        ])

        add(.education, [
            "coursera", "udemy", "udacity", "edx", "skillshare", "duolingo",
            "khan academy", "masterclass", "pluralsight", "codecademy", "chegg",
            "kaplan", "pearson", "barnes and noble", "waterstones", "blackwells",
            "kindle", "brilliant", "rosetta stone", "babbel"
        ])

        add(.business, [
            "wework", "regus", "fedex", "ups", "dhl", "usps", "staples",
            "office depot", "indeed", "upwork", "fiverr", "zoom", "slack",
            "atlassian", "asana", "salesforce", "quickbooks", "stripe", "shopify",
            "aws", "google cloud", "digitalocean", "godaddy", "namecheap"
        ])

        add(.savings, [
            "vanguard", "fidelity", "charles schwab", "robinhood", "coinbase",
            "wealthfront", "betterment", "acorns", "etrade", "interactive brokers",
            "nutmeg", "trading 212", "freetrade", "kraken", "binance"
        ])

        return m
    }()
}
