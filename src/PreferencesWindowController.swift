import Cocoa

final class PreferencesWindowController: NSWindowController {
    private let preferencesViewController = PreferencesViewController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentViewController = preferencesViewController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class PreferencesViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "업데이트")
    private let descriptionLabel = NSTextField(labelWithString: "새 버전이 있으면 하루 2번 자동으로 확인하고 다운로드합니다.")
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "자동 업데이트 확인", target: nil, action: nil)
    private let footerLabel = NSTextField(labelWithString: "꺼두면 자동 확인과 자동 다운로드가 중지됩니다. 이미 준비된 업데이트는 다음 실행 시 다시 안내됩니다.")

    override func loadView() {
        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, descriptionLabel, autoUpdateCheckbox, footerLabel].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.alignment = .left

        descriptionLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 2
        descriptionLabel.lineBreakMode = .byWordWrapping

        autoUpdateCheckbox.target = self
        autoUpdateCheckbox.action = #selector(toggleAutoUpdate(_:))
        autoUpdateCheckbox.state = UpdateManager.shared.isAutoUpdateEnabled() ? .on : .off
        autoUpdateCheckbox.font = NSFont.systemFont(ofSize: 13, weight: .medium)

        footerLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.maximumNumberOfLines = 3
        footerLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [titleLabel, descriptionLabel, autoUpdateCheckbox, footerLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        rootView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -24)
        ])

        self.view = rootView
    }

    @objc private func toggleAutoUpdate(_ sender: NSButton) {
        UpdateManager.shared.setAutoUpdateEnabled(sender.state == .on)
    }
}
