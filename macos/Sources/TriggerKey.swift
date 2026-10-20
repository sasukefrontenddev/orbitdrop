import ApplicationServices
import Foundation

struct TriggerKey: Equatable {
    let code: CGKeyCode
    let label: String

    private static let defaultsKey = "OrbitDropTriggerKeyCode"

    static let supported: [TriggerKey] = [
        TriggerKey(code: 49, label: "Space"),
        TriggerKey(code: 97, label: "F6"),
        TriggerKey(code: 98, label: "F7"),
        TriggerKey(code: 100, label: "F8"),
        TriggerKey(code: 101, label: "F9"),
        TriggerKey(code: 109, label: "F10"),
        TriggerKey(code: 103, label: "F11"),
        TriggerKey(code: 111, label: "F12"),
        TriggerKey(code: 0, label: "A"), TriggerKey(code: 11, label: "B"),
        TriggerKey(code: 8, label: "C"), TriggerKey(code: 2, label: "D"),
        TriggerKey(code: 14, label: "E"), TriggerKey(code: 3, label: "F"),
        TriggerKey(code: 5, label: "G"), TriggerKey(code: 4, label: "H"),
        TriggerKey(code: 34, label: "I"), TriggerKey(code: 38, label: "J"),
        TriggerKey(code: 40, label: "K"), TriggerKey(code: 37, label: "L"),
        TriggerKey(code: 46, label: "M"), TriggerKey(code: 45, label: "N"),
        TriggerKey(code: 31, label: "O"), TriggerKey(code: 35, label: "P"),
        TriggerKey(code: 12, label: "Q"), TriggerKey(code: 15, label: "R"),
        TriggerKey(code: 1, label: "S"), TriggerKey(code: 17, label: "T"),
        TriggerKey(code: 32, label: "U"), TriggerKey(code: 9, label: "V"),
        TriggerKey(code: 13, label: "W"), TriggerKey(code: 7, label: "X"),
        TriggerKey(code: 16, label: "Y"), TriggerKey(code: 6, label: "Z")
    ]

    static var current: TriggerKey {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else { return supported[0] }
        let stored = UserDefaults.standard.integer(forKey: defaultsKey)
        return supported.first(where: { Int($0.code) == stored }) ?? supported[0]
    }

    static func save(_ key: TriggerKey) {
        UserDefaults.standard.set(Int(key.code), forKey: defaultsKey)
    }
}
