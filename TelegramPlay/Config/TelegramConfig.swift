import Foundation

enum TelegramConfig {
    static var apiId: Int32 {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TelegramApiId") as? String,
              let id = Int32(raw), id != 0 else {
            fatalError("Set TELEGRAM_API_ID in Config/Secrets.xcconfig (see Secrets.xcconfig.example).")
        }
        return id
    }

    static var apiHash: String {
        guard let hash = Bundle.main.object(forInfoDictionaryKey: "TelegramApiHash") as? String,
              !hash.isEmpty, hash != "your_api_hash_here" else {
            fatalError("Set TELEGRAM_API_HASH in Config/Secrets.xcconfig.")
        }
        return hash
    }
}
