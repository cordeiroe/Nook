import Foundation
import NookCore

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n)) : s.padding(toLength: n, withPad: " ", startingAt: 0)
}
func header(_ s: String) { print("\n\u{001B}[1m== \(s)\u{001B}[0m") }
func bar(_ ratio: Double, width: Int = 22) -> String {
    let filled = max(0, min(width, Int(ratio * Double(width))))
    return "[" + String(repeating: "#", count: filled) + String(repeating: ".", count: width - filled) + "]"
}

let config = Config.load()

var mark = Date()
func lap(_ label: String) {
    print(String(format: "  %-22s %.2fs", (label as NSString).utf8String!, Date().timeIntervalSince(mark)))
    mark = Date()
}

header("TEMPOS")
let builder = DashboardBuilder()
lap("init + migração")
let quota = await MiniMaxClient.shared.quotaBlocking()
lap("MiniMax HTTP")
_ = quota
let snap = await builder.build(config: config)
lap("build completo")

for provider in snap.providers {
    header("\(provider.name.uppercased())  ->  anel \(provider.percent)%")
    for meter in provider.meters {
        let flag = meter.estimated ? "~" : " "
        let head = meter.countsForHeadline ? "*" : " "
        print("  \(head)\(flag) \(pad(meter.title, 16)) \(bar(meter.ratio)) \(pad("\(meter.percent)%", 6)) \(pad(meter.detail, 24)) \(meter.footnote ?? "")")
    }
    if provider.sessions.isEmpty {
        print("     sem sessões vivas")
    } else {
        for s in provider.sessions {
            let dot = s.status == .busy ? "\u{001B}[33m*\u{001B}[0m" : "\u{001B}[32m.\u{001B}[0m"
            print("   \(dot) \(pad(s.name, 40)) <\(s.status.rawValue)>  \(s.shortDirectory)  \(Format.elapsed(since: s.updatedAt))")
        }
    }
    if let w = provider.warning { print("     \u{001B}[2m\(w)\u{001B}[0m") }
}

if let m = snap.nowPlaying {
    header("TOCANDO")
    print("  \(m.title)")
    print("  \(m.artist) · \(m.album)")
    print("  \(m.app)  \(m.isPlaying ? "tocando" : "pausado")  \(NowPlaying.clock(m.position(at: Date()))) / \(NowPlaying.clock(m.duration))  \(bar(m.progress()))")
    print("  capa: \(m.artworkURL?.absoluteString ?? "sem capa")")
}

header("LEGENDA")
print("  *  entra no anel (limite real)      ~  teto estimado, não vem do provider")

if let h = snap.headline {
    header("MAIOR PRESSÃO")
    print("  \(h.title): \(h.percent)%  (\(h.detail))")
}
print("")
