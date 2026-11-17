import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared

    // README 스크린샷 생성: TailQuestions --snapshot <폴더>
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
        let dir = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "docs"
        app.setActivationPolicy(.prohibited)
        Snapshot.run(outDir: dir)
        exit(0)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
