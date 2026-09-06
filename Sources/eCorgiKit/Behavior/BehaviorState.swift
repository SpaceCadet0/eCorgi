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

    /// Действие спрайта, которым состояние себя показывает.
    /// Объявляется здесь, а не литералом внутри `update`, чтобы о нём могли
    /// узнать снаружи — например, меню проверки анимаций.
    var spriteAction: SpriteAction { get }

    /// Сколько последних кадров крутить после первого прохода.
    /// Ноль — обычный цикл; см. `SpriteAnimator.tail`.
    var animationTail: Int { get }

    /// Темп для проверки анимации в отрыве от поведения.
    /// У состояний, чей темп берётся из `tuning`, здесь стоит значение
    /// по умолчанию — для просмотра этого достаточно.
    var previewFPS: Double { get }

    func enter(_ pet: Pet)
    func update(_ pet: Pet, dt: TimeInterval) -> BehaviorTransition
    func exit(_ pet: Pet)
}

public extension BehaviorState {
    var isInterruptibleByTimer: Bool { true }
    var animationTail: Int { 0 }
    func exit(_ pet: Pet) {}
}
