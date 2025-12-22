import Foundation

/// Global registry for staging cleanup on process termination (e.g., Control+C).
///
/// This actor maintains a list of cleanup handlers that are invoked when
/// the process receives SIGINT or SIGTERM. Each staging registers a cleanup
/// handler when created and unregisters it when properly discarded.
///
/// Usage:
/// ```swift
/// // Register cleanup handler
/// let id = await StagingCleanupRegistry.shared.register {
///     await staging.discard()
/// }
///
/// // Unregister when done
/// await StagingCleanupRegistry.shared.unregister(id)
/// ```
public actor StagingCleanupRegistry {
    /// Shared singleton instance.
    public static let shared = StagingCleanupRegistry()

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
    /// Call this when the staging is properly cleaned up to avoid
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
            Task.immediate {
                await StagingCleanupRegistry.shared.executeCleanup()
                // Exit with the standard signal exit code
                exit(130) // 128 + SIGINT (2)
            }
        }

        // Set up SIGTERM handler
        signal(SIGTERM) { _ in
            Task.immediate {
                await StagingCleanupRegistry.shared.executeCleanup()
                exit(143) // 128 + SIGTERM (15)
            }
        }
    }
}
