import Foundation

/// Идентификатор поведения. Совпадает с ключами в `behaviors.json`.
public enum BehaviorID: String, CaseIterable, Codable, Sendable {
    case idle
    case walk
    case sit
    case settleDown
    case sleep
    case wakeUp
    case scratch
    case runFromCursor
    case climb
    case hang
    case hop
    case jumpDown
    case fall
    case land
    case drag
}

/// Чем закончился тик состояния.
public enum BehaviorTransition: Equatable {
    /// Продолжаем; автомат сам решит, не пора ли сменить состояние по таймеру.
    case stay
    /// Состояние отработало своё (анимация доиграла, цель достигнута) —
    /// автомат выбирает следующее по весам.
    case done
    /// Состояние само требует конкретного перехода.
    case switchTo(BehaviorID)
}

/// Одно поведение питомца.
public protocol BehaviorState: AnyObject {
    var id: BehaviorID { get }
    /// Может ли автомат прервать состояние по истечении таймера.
    /// `false` у Drag/Fall — они заканчиваются только по событию.
    var isInterruptibleByTimer: Bool { get }

    func enter(_ pet: Pet)
    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition
    func exit(_ pet: Pet)
}

public extension BehaviorState {
    var isInterruptibleByTimer: Bool { true }
    func exit(_ pet: Pet) {}
}
