import AppKit

var retainedDelegate: AnyObject?

MainActor.assumeIsolated {
    if let index = CommandLine.arguments.firstIndex(of: "--self-test") {
        let directory = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : FileManager.default.temporaryDirectory.path
        SelfTest.run(outputDirectory: directory)
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
