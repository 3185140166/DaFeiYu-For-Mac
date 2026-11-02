import Foundation

struct AgentBubblePlacement {
    let frame: CGRect
    let above: Bool
    let tailX: CGFloat
}

enum AgentBubbleGeometry {
    static func place(near pet: CGRect, visible: CGRect, desiredHeight: CGFloat) -> AgentBubblePlacement {
        let margin: CGFloat = 10
        let width = min(300, max(120, visible.width - margin * 2))
        let height = min(desiredHeight, max(120, visible.height - margin * 2))
        let x = min(max(pet.midX - width / 2, visible.minX + margin), visible.maxX - width - margin)
        let aboveY = pet.maxY + 6
        let belowY = pet.minY - height - 6
        let above = aboveY + height <= visible.maxY - margin ||
            (belowY < visible.minY + margin && visible.maxY - pet.maxY >= pet.minY - visible.minY)
        let y = min(max(above ? aboveY : belowY, visible.minY + margin), visible.maxY - height - margin)
        return AgentBubblePlacement(frame: CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height),
                                    above: above, tailX: min(max(pet.midX - x, 28), width - 28))
    }
}
