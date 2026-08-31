import AppKit
import SwiftUI

/// A marca do Nook: a palavra com um sorriso por baixo do "oo".
///
/// O arco tem a mesma largura e a mesma espessura do traço de alerta, e por
/// isso ele É o traço: passando do limite, o sorriso acende em laranja em vez
/// de aparecer um elemento novo na tela.
enum Brand {
    static let wordmark = "nook"

    /// Só o alerta usa laranja. Em qualquer outro estado a marca fica na cor
    /// do texto, senão o laranja perde o significado de aviso.
    static let ink = Color(red: 0.925, green: 0.910, blue: 0.890)     // #ece8e3
    static let alert = Color(red: 0.961, green: 0.576, blue: 0.0)     // #f59300

    private static var registered = false

    /// Registra a fonte empacotada. Sem isso o `NSFont(name:)` falha em
    /// silêncio e a marca cai numa fonte do sistema.
    static func registerFont() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque-SemiBold", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(size: CGFloat) -> Font {
        registerFont()
        if NSFont(name: "BricolageGrotesque-SemiBold", size: size) != nil {
            return .custom("BricolageGrotesque-SemiBold", size: size)
        }
        // Reserva para quando o recurso não estiver no bundle.
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// O sorriso: a borda inferior de uma caixa com os cantos de baixo
/// arredondados.
///
/// Não é uma parábola. O CSS do desenho pede `border-radius: 0 0 26px 26px`
/// numa caixa de 26x8, e o navegador encolhe raios que não cabem: o raio real
/// vira 8. O traço fica reto no meio com as pontas viradas para cima, e é isso
/// que faz o sorriso caber sob o `oo` em vez de abraçar a palavra inteira.
struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        let raio = min(rect.height, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY - raio))
        p.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
            radius: raio
        )
        p.addLine(to: CGPoint(x: rect.maxX - raio, y: rect.maxY))
        p.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: raio
        )
        return p
    }
}

/// Marca desenhada dentro do recorte, quando ele é virtual. Num notch físico
/// não existem pixels para desenhar.
struct BrandMark: View {
    /// Altura do recorte, para a marca acompanhar telas com barra de menus
    /// de alturas diferentes.
    let notchHeight: CGFloat
    /// Fração do medidor mais pressionado, quando passa do limite configurado.
    let alert: Double?

    private var size: CGFloat { min(13, max(9, notchHeight * 0.44)) }
    /// Proporções medidas para o arco ficar sob o `oo`. Na largura do desenho
    /// as pontas subiam dentro do `n` e do `k`.
    private var smileWidth: CGFloat { size * 1.38 }
    private var smileDepth: CGFloat { size * 0.38 }
    private var smileLift: CGFloat { size * 0.23 }
    private var stroke: CGFloat { alert == nil ? 1.5 : 2 }

    private var color: Color {
        guard let alert else { return Brand.ink.opacity(0.5) }
        return alert >= 0.92 ? Brand.alert : Theme.alertTint(alert)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(Brand.wordmark)
                .font(Brand.font(size: size))
                .kerning(size * 0.02)
                .foregroundStyle(Brand.ink)
                .fixedSize()

            Smile()
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: smileWidth, height: smileDepth)
                .offset(y: -smileLift)
                .animation(.easeInOut(duration: 0.3), value: alert != nil)
        }
    }
}
