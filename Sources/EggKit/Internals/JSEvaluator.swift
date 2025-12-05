import Foundation
import JavaScriptCore

struct JSEvaluator {
    private let vm: JSVirtualMachine
    private let context: JSContext?

    init() {
        vm = JSVirtualMachine()
        context = JSContext(virtualMachine: vm)
    }

    func evaluate(_ source: String) -> JSValue? {
        context?.exception = nil
        let value = context?.evaluateScript(source)
        if context?.exception != nil {
            return nil
        }
        return value
    }
}
