import XCTest
@testable import eCorgiKit

/// Анимации доигрываются целиком и идут ровно при любой настройке скорости.
final class AnimationPacingTests: XCTestCase {

    private func makePet(speed: Double = 1) -> (Pet, SettingsStore) {
        let settings = SettingsStore.testStore()
        settings.speedMultiplier = speed
        let ground = Ledge(y: 0, minX: 0, maxX: 1200, kind: .ground)
        let pet = Pet(atlas: SpriteAtlas(),
                      environment: ScreenEnvironment(fixedLedges: [ground],
                                                     worldBounds: CGRect(x: 0, y: 0, width: 1200, height: 900)),
                      settings: settings,
                      random: .fixed([0.5]),
                      position: CGPoint(x: 400, y: 0))
        return (pet, settings)
    }

    override func tearDown() {
        SettingsStore.testStore().speedMultiplier = 1
        super.tearDown()
    }

    /// Кадры, показанные, пока питомец остаётся в состоянии.
    private func framesShown(_ pet: Pet, in behavior: BehaviorID, tick: TimeInterval = 1.0 / 60) -> Set<Int> {
        var seen = Set<Int>()
        for _ in 0..<3000 {
            pet.update(tick)
            guard pet.currentBehavior == behavior else { break }
            seen.insert(pet.animator.frameIndex)
        }
        return seen
    }

    func testOneShotStatesPlayEveryFrameAtAnySpeed() {
        for speed in [0.5, 1, 2] {
            for behavior in [BehaviorID.settleDown, .wakeUp, .land, .sit] {
                let (pet, _) = makePet(speed: speed)
                pet.update(0)
                pet.force(behavior)
                let seen = framesShown(pet, in: behavior)
                XCTAssertEqual(seen.count, pet.atlas.frames(for: Pet.animations[behavior]!.action).count,
                               "\(behavior.rawValue) при скорости \(speed) показал не все кадры")
                XCTAssertNotEqual(pet.currentBehavior, behavior, "\(behavior.rawValue) должен закончиться сам")
            }
        }
    }

    func testHopShowsEveryFrameAtAnySpeed() {
        for speed in [0.5, 1, 2] {
            let (pet, _) = makePet(speed: speed)
            pet.update(0)
            pet.force(.hop)
            var seen = Set<Int>()
            var lastInAir = 0
            for _ in 0..<3000 {
                pet.update(1.0 / 120)
                guard pet.currentBehavior == .hop else { break }
                seen.insert(pet.animator.frameIndex)
                lastInAir = pet.animator.frameIndex
            }
            let total = pet.atlas.frames(for: .hop).count
            XCTAssertGreaterThanOrEqual(seen.count, total - 1, "Подскок при скорости \(speed) потерял кадры")
            XCTAssertGreaterThanOrEqual(lastInAir, total - 3,
                                        "При скорости \(speed) анимация должна кончаться вместе с полётом")
        }
    }

    func testClimbLoopsOnlyItsLastTwoFrames() {
        XCTAssertEqual(Pet.animations[.climb]?.tail, 2)
    }

    func testLoopTicksAtLeastTwicePerAnimationFrame() {
        for speed in [0.5, 1, 2] {
            let (pet, settings) = makePet(speed: speed)
            for behavior in [BehaviorID.idle, .walk, .sit, .sleep] {
                pet.force(behavior)
                pet.update(1.0 / 30)
                guard pet.currentBehavior == behavior else { continue }
                let animationRate = pet.animator.fps * settings.speedMultiplier
                XCTAssertGreaterThanOrEqual(pet.desiredFPS, min(60, animationRate * 2),
                                            "\(behavior.rawValue) при скорости \(speed): тиков меньше, чем нужно кадрам")
            }
        }
    }

    func testScratchIsNotChosenWhileItHasNoFramesOfItsOwn() {
        // Своих кадров у `scratch` нет, а подмена на `sit` выглядит как
        // оборванное сидение — поэтому таблица переходов его не предлагает.
        let config = BehaviorConfig.load()
        let offered = config.states.values.flatMap(\.next).map(\.state)
        XCTAssertFalse(offered.contains(.scratch))
    }
}
