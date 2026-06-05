import Cocoa
import Foundation

enum UpdateInstaller {
    static func installAndRelaunch(from dmgURL: URL, applicationBundleURL: URL = Bundle.main.bundleURL) {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskgpt-update-\(UUID().uuidString).sh")

        let destinationPath = shellQuote(applicationBundleURL.path)
        let dmgPath = shellQuote(dmgURL.path)
        let script = """
        #!/bin/bash
        set -euo pipefail

        DMG_PATH=\(dmgPath)
        APP_PATH=\(destinationPath)
        MOUNT_POINT="$(mktemp -d /tmp/deskgpt-update-mount.XXXXXX)"

        cleanup() {
            hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
            rm -rf "$MOUNT_POINT"
        }

        trap cleanup EXIT

        hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_POINT" -quiet

        while pgrep -x DeskGPT >/dev/null; do
            sleep 0.5
        done

        rm -rf "$APP_PATH"
        ditto "$MOUNT_POINT/DeskGPT.app" "$APP_PATH"
        open "$APP_PATH"
        rm -f "$DMG_PATH"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            print("⚠️ Unable to write update installer helper: \(error.localizedDescription)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]

        do {
            try process.run()
        } catch {
            print("⚠️ Unable to launch update installer helper: \(error.localizedDescription)")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
