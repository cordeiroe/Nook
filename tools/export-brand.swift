// Gera docs/hero.png e docs/logo.png a partir do mesmo Brand.swift que o app
// usa, para a arte do README nunca divergir do que aparece na tela.
//
//   swift tools/export-brand.swift
//
// Roda concatenando Brand.swift antes deste arquivo, porque um script solto do
// Swift não importa alvos do SwiftPM.
import AppKit
import SwiftUI
import CoreText

CTFontManagerRegisterFontsForURL(
    URL(fileURLWithPath: "/Users/cordeiroe/Projects/privateProjects/Nook/Resources/BricolageGrotesque-SemiBold.ttf") as CFURL,
    .process, nil)

let laranja = Color(red: 0.961, green: 0.576, blue: 0)
let tinta = Color(red: 0.925, green: 0.910, blue: 0.890)

/// Como peça de marca o sorriso vai laranja, igual ao artboard de identidade.
/// Na interface ele só acende assim em alerta, e essa regra continua valendo lá.
struct Logo: View {
    let corpo: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Text("nook")
                .font(.custom("BricolageGrotesque-SemiBold", size: corpo))
                .kerning(corpo * 0.02).foregroundStyle(tinta).fixedSize()
            Smile(thickness: max(1.5, corpo * 0.115))
                .fill(laranja)
                .frame(width: corpo * 1.58, height: corpo * 0.33)
                .offset(y: -(corpo * 0.23 - max(1.5, corpo * 0.115) / 2))
        }
    }
}

struct Barra: View {
    let titulo: String, detalhe: String, fracao: Double, cor: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(titulo).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.88))
                Spacer()
                Text("\(Int(fracao*100))%").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.11))
                    Capsule().fill(cor).frame(width: g.size.width * fracao)
                }
            }.frame(height: 5)
            Text(detalhe).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.34))
        }
    }
}

/// Capa: o recorte com a marca e o painel aberto logo abaixo, como no uso.
struct Capa: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.31, green: 0.19, blue: 0.42),
                                    Color(red: 0.17, green: 0.10, blue: 0.24),
                                    Color(red: 0.12, green: 0.08, blue: 0.17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Logo(corpo: 14)
                    .frame(width: 220, height: 34)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 13,
                                               bottomTrailingRadius: 13, topTrailingRadius: 0,
                                               style: .continuous).fill(Color.black))
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 3) {
                        ForEach(Array(["gauge.with.dots.needle.33percent","calendar","terminal","music.note","doc.on.clipboard","tray.full"].enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 5) {
                                Image(systemName: s).font(.system(size: 12, weight: .medium))
                                if i == 0 { Text("Consumo").font(.system(size: 11.5, weight: .medium)) }
                            }
                            .foregroundStyle(.white.opacity(i == 0 ? 0.95 : 0.42))
                            .padding(.horizontal, i == 0 ? 9 : 6).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(i == 0 ? 0.15 : 0)))
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "asterisk").font(.system(size: 14, weight: .medium))
                        Text("Claude").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text("82%").font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(laranja)
                    }.foregroundStyle(.white)
                    Barra(titulo: "Sessão (5h)", detalhe: "12.3M / 15.0M · reseta 19:04", fracao: 0.82, cor: laranja)
                    Barra(titulo: "Semana", detalhe: "22.1M / 90.0M · reseta Sex. 14:00", fracao: 0.25,
                          cor: Color(red: 0.20, green: 0.86, blue: 0.50))
                }
                .padding(15)
                .frame(width: 380, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black))
            }
            .padding(.top, 0)
        }
        .frame(width: 820, height: 258)
    }
}

struct Marca: View {
    var body: some View { Logo(corpo: 72).frame(width: 440, height: 180).background(Color.black) }
}

func exportar<V: View>(_ view: V, _ escala: CGFloat, _ destino: String) {
    let base = NSHostingView(rootView: view)
    let t = base.fittingSize
    let v = NSHostingView(rootView: view.frame(width: t.width, height: t.height)
        .scaleEffect(escala, anchor: .topLeading)
        .frame(width: t.width * escala, height: t.height * escala, alignment: .topLeading))
    v.frame = CGRect(origin: .zero, size: CGSize(width: t.width * escala, height: t.height * escala))
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: destino))
    print("  \(URL(fileURLWithPath: destino).lastPathComponent)  \(Int(t.width*escala))x\(Int(t.height*escala))")
}

let dir = "/Users/cordeiroe/Projects/privateProjects/Nook/docs/"
exportar(Capa(), 2, dir + "hero.png")
exportar(Marca(), 2, dir + "logo.png")
