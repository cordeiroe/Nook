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

/// O sorriso: uma curva contínua que engrossa no meio e afina até sumir nas
/// pontas.
///
/// A espessura variável vem do CSS do desenho. Com a borda de baixo em `w` e as
/// laterais em zero, ela interpola de `w` até nada ao longo do canto
/// arredondado. Um caminho traçado com espessura constante não reproduz isso,
/// então a figura é preenchida entre duas curvas que partem e chegam no mesmo
/// ponto e por isso se fecham em ponta.
///
/// A geometria literal do CSS seria canto, reta, canto. Nas proporções do
/// recorte quase metade do arco virava reta, e no grid de pixel de uma tela 1x
/// isso endurecia o desenho. Duas cúbicas simétricas dão a mesma silhueta sem
/// o trecho reto.
struct Smile: Shape {
    /// Espessura no ponto mais grosso, no meio do arco.
    var thickness: CGFloat

    /// Quanto os controles se afastam do centro. Mais alto deixa as pontas
    /// saindo na horizontal, como numa boca, em vez de mergulhando.
    private let spread: CGFloat = 0.37

    func path(in rect: CGRect) -> Path {
        let profundidade = rect.height
        let w = min(thickness, profundidade)
        guard rect.width > 0, profundidade > 0 else { return Path() }

        let esquerda = CGPoint(x: rect.minX, y: rect.minY)
        let direita = CGPoint(x: rect.maxX, y: rect.minY)
        let dx = rect.width * spread

        /// Controles de uma cúbica simétrica cuja flecha no centro é `flecha`.
        /// O fator 4/3 compensa o encolhimento da Bézier em relação aos
        /// pontos de controle.
        func controles(_ flecha: CGFloat) -> (CGPoint, CGPoint) {
            let y = rect.minY + flecha * 4 / 3
            return (CGPoint(x: rect.minX + dx, y: y), CGPoint(x: rect.maxX - dx, y: y))
        }

        let (externo1, externo2) = controles(profundidade)
        let (interno1, interno2) = controles(profundidade - w)

        var p = Path()
        p.move(to: esquerda)
        p.addCurve(to: direita, control1: externo1, control2: externo2)
        p.addCurve(to: esquerda, control1: interno2, control2: interno1)
        p.closeSubpath()
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
    /// as pontas subiam dentro do `n` e do `k`. Com a curva contínua as pontas
    /// saem mais rasas, então ela pode ser um pouco mais larga sem encostar.
    private var smileWidth: CGFloat { size * 1.58 }
    private var smileDepth: CGFloat { size * 0.33 }
    private var thickness: CGFloat { max(alert == nil ? 1.5 : 2, size * (alert == nil ? 0.115 : 0.155)) }
    /// O traço preenchido ocupa de `base - espessura` até a base, enquanto o
    /// traçado ficava centrado na curva. Descontar metade da espessura mantém a
    /// tinta no mesmo lugar de antes.
    private var smileLift: CGFloat { size * 0.23 - thickness / 2 }

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

            Smile(thickness: thickness)
                .fill(color)
                .frame(width: smileWidth, height: smileDepth)
                .offset(y: -smileLift)
                .animation(.easeInOut(duration: 0.3), value: alert != nil)
        }
    }
}
