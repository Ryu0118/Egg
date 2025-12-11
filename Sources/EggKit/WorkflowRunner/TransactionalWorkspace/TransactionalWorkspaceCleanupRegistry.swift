import Foundation

/// Global registry for transactional workspace cleanup on process termination (e.g., Control+C).
///
/// This actor maintains a list of cleanup handlers that are invoked when
/// the process receives SIGINT or SIGTERM. Each transactional workspace registers a cleanup
/// handler when created and unregisters it when properly discarded.
///
/// Usage:
/// ```swift
/// // Register cleanup handler
/// let id = await TransactionalWorkspaceCleanupRegistry.shared.register {
///     await transactionalWorkspace.discard()
/// }
///
/// // Unregister when done
/// await TransactionalWorkspaceCleanupRegistry.shared.unregister(id)
/// ```
public actor TransactionalWorkspaceCleanupRegistry {
    /// Shared singleton instance.
    public static let shared = TransactionalWorkspaceCleanupRegistry()

    /// Unique identifier for registered cleanup handlers.
    public struct HandlerID: Hashable, Sendable {
        let uuid: UUID
    }

    private var handlers: [HandlerID: @Sendable () async -> Void] = [:]
    private var isSignalHandlerInstalled = false

    private init() {}

    /// Registers a cleanup handler to be called on process termination.
    ///
    /// - Parameter handler: Async closure to execute during cleanup
    /// - Returns: A unique identifier for this handler (used for unregistration)
    public func register(_ handler: @escaping @Sendable () async -> Void) -> HandlerID {
        let id = HandlerID(uuid: UUID())
        handlers[id] = handler

        if !isSignalHandlerInstalled {
            installSignalHandlers()
            isSignalHandlerInstalled = true
        }

        return id
    }

    /// Unregisters a previously registered cleanup handler.
    ///
    /// Call this when the transactional workspace is properly cleaned up to avoid
    /// unnecessary cleanup attempts during signal handling.
    ///
    /// - Parameter id: The handler identifier returned from `register`
    public func unregister(_ id: HandlerID) {
        handlers.removeValue(forKey: id)
    }

    /// Executes all registered cleanup handlers.
    ///
    /// This is called automatically by signal handlers but can also
    /// be called manually if needed.
    public func executeCleanup() async {
        for (_, handler) in handlers {
            await handler()
        }
        handlers.removeAll()
    }

    /// Installs signal handlers for SIGINT and SIGTERM.
    private nonisolated func installSignalHandlers() {
        // Set up SIGINT handler (Control+C)
        signal(SIGINT) { _ in
            // Signal handlers must be synchronous and signal-safe.
            // We use a detached task to call async cleanup code.
            Task {
                await TransactionalWorkspaceCleanupRegistry.shared.executeCleanup()
                // Exit with the standard signal exit code
                exit(130) // 128 + SIGINT (2)
            }
            // Give the task a moment to start, then prevent default handling
            // by blocking here (the exit() above will terminate the process)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
        }

        // Set up SIGTERM handler
        signal(SIGTERM) { _ in
            Task {
                await TransactionalWorkspaceCleanupRegistry.shared.executeCleanup()
                exit(143) // 128 + SIGTERM (15)
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
        }
    }
}
