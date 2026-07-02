import Foundation

public enum StudioUIPhase: Sendable, Equatable {
    case idle
    case loading(operation: String)
    case completed(operation: String)
    case failed(operation: String, message: String)
    case cancelled(operation: String)
}

public struct StudioUIState: Sendable, Equatable {
    public private(set) var phase: StudioUIPhase = .idle
    public private(set) var selectedCollection: CollectionID?
    public private(set) var browseLimitReached = false

    public init() {}

    public var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    public mutating func begin(_ operation: String) {
        phase = .loading(operation: operation)
    }

    public mutating func complete(_ operation: String) {
        phase = .completed(operation: operation)
    }

    public mutating func fail(_ operation: String, error: any Error) {
        phase = .failed(operation: operation, message: String(describing: error))
    }

    public mutating func cancel(_ operation: String) {
        phase = .cancelled(operation: operation)
    }

    public mutating func select(_ collection: CollectionID?) {
        selectedCollection = collection
        browseLimitReached = false
    }

    public mutating func setBrowseLimitReached(_ reached: Bool) {
        browseLimitReached = reached
    }
}
