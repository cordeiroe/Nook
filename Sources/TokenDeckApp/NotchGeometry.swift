import AppKit

/// Onde fica o notch e quanto espaco ele ocupa.
///
/// Em Macs com notch fisico o macOS expoe as duas faixas de menu que sobram
/// dos lados; o que falta entre elas e o notch. Em telas sem notch usamos a
/// propria altura da barra de menus como um notch virtual no centro do topo,
/// que e como o painel se comporta em monitor externo.
struct NotchGeometry: Equatable {
    let screenNumber: Int
    let screenFrame: CGRect
    let notchRect: CGRect
    let isPhysical: Bool

    /// Largura do notch virtual quando a tela nao tem um de verdade.
    private static let virtualWidth: CGFloat = 200
    private static let minimumBarHeight: CGFloat = 24

    static func detect(preferring screenNumber: Int?) -> NotchGeometry? {
        let candidates = NSScreen.screens
        guard !candidates.isEmpty else { return nil }

        let chosen: NSScreen
        if let screenNumber, let match = candidates.first(where: { id(of: $0) == screenNumber }) {
            chosen = match
        } else if let notched = candidates.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            chosen = notched
        } else {
            chosen = NSScreen.main ?? candidates[0]
        }
        return make(for: chosen)
    }

    private static func make(for screen: NSScreen) -> NotchGeometry? {
        guard let id = id(of: screen) else { return nil }
        let frame = screen.frame

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let height = left.height
            guard width > 0, height > 0 else { return nil }
            return NotchGeometry(
                screenNumber: id,
                screenFrame: frame,
                notchRect: CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height),
                isPhysical: true
            )
        }

        let barHeight = max(frame.maxY - screen.visibleFrame.maxY, minimumBarHeight)
        return NotchGeometry(
            screenNumber: id,
            screenFrame: frame,
            notchRect: CGRect(x: frame.midX - virtualWidth / 2, y: frame.maxY - barHeight,
                              width: virtualWidth, height: barHeight),
            isPhysical: false
        )
    }

    static func id(of screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    // MARK: - Frames do painel

    /// Em repouso o painel cobre exatamente o notch e nao desenha nada.
    var collapsedFrame: CGRect { notchRect }

    /// Aberto, ele desce a partir da base do notch, centrado no mesmo eixo.
    func expandedFrame(cardSize: CGSize) -> CGRect {
        let width = max(cardSize.width, notchRect.width)
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: notchRect.minY - cardSize.height,
            width: width,
            height: cardSize.height + notchRect.height
        )
    }
}
