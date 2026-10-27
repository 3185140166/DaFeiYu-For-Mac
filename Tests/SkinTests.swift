import AppKit
import CoreGraphics

enum L10nKey { case skinBasin, skinMaid, skinHoodie }
extension Bundle {
    static var module: Bundle { Bundle(path: CommandLine.arguments[1])! }
}

@main struct SkinTests {
    @MainActor static func main() throws {
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        let hoodie = PetSkin.skin(at: PetSkin.defaultSkinIndex)
        check(hoodie.prefix == "hoodie" && hoodie.expressionCount == 1, "Wrong default or expression count")
        check(hoodie.resourceName(for: 0) == "hoodie_stand" && hoodie.resourceName(for: 1) == "hoodie_face_happy", "Wrong artwork mapping")
        check(hoodie.resourceName(for: 99) == hoodie.standResource, "Unsafe expression index")
        for skin in PetSkin.skins {
            check(PetArtworkStore.shared.sourceImage(skin: skin, expression: 0) != nil, "Missing standing art")
            check(PetArtworkStore.shared.availableExpressionCount(skin: skin) == skin.expressionCount, "Missing expression")
        }
        let idle = PetArtworkStore.shared.sourceImage(skin: hoodie, expression: 0)!
        let happy = PetArtworkStore.shared.sourceImage(skin: hoodie, expression: 1)!
        check(idle.width == happy.width && idle.height == happy.height && idle.width == 640, "Mismatched canvas")
        let bitmap = PetBitmap(source: idle, pixelWidth: 640, pixelHeight: 640)!
        check(bitmap.alpha(x: 0, y: 0) == 0 && bitmap.alpha(x: 639, y: 639) == 0, "Opaque image corners")
        let view = PetView(frame: .zero)
        view.artworkSource = { skin, expression in PetArtworkStore.shared.sourceImage(skin: skin, expression: expression) }
        view.skinIndex = hoodie.index
        check(view.cycleExpression() == 1 && view.cycleExpression() == 0, "Hoodie does not toggle idle/happy")
        view.mode = .perch
        let expected = (hoodie.headX1 - hoodie.headX0) / (hoodie.headY1 - hoodie.headY0)
        check(abs(view.perchHeadAspect - expected) < 0.0001, "Rotated head aspect is stretched")
        let perched = PetArtworkStore.shared.perchArtwork(skin: hoodie, expression: 0, pixelWidth: 192, aspect: view.perchHeadAspect)!
        let rep = NSBitmapImageRep(cgImage: perched.image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/hoodie-perch-preview.png"))
        check(Bundle.module.url(forResource: "HoodieArtworkLicense", withExtension: "txt") != nil, "Missing bundled license")
        let suite = "BaifanYuSkinTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0, forKey: AppSettings.Key.skinIndex)
        AppSettings.adoptHoodieDefaultIfNeeded(in: defaults)
        check(defaults.integer(forKey: AppSettings.Key.skinIndex) == hoodie.index, "Existing settings did not adopt hoodie")
        defaults.set(1, forKey: AppSettings.Key.skinIndex)
        AppSettings.adoptHoodieDefaultIfNeeded(in: defaults)
        check(defaults.integer(forKey: AppSettings.Key.skinIndex) == 1, "Manual choice overwritten on relaunch")
        print("PASS: default migration, later manual choice, bundled skins, idle/happy cycling, matching transparent canvases, rotated head geometry and bundled license")
    }
}
