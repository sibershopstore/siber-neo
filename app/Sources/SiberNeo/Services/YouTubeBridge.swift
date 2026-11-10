import AppKit

/// Reads and controls YouTube and YouTube Music playing in Chromium-based browsers
/// (Chrome, Brave, Edge, Arc) through AppleScript. Runs on a background queue to keep the UI responsive.
/// Requires "View → Developer → Allow JavaScript from Apple Events" in the browser.
final class YouTubeBridge {
    struct Browser {
        let name: String
        let bundleID: String
    }

    struct Snapshot: Decodable, Equatable {
        let title: String
        let artist: String
        let duration: Double
        let position: Double
        let paused: Bool
        let art: String
        let id: String
    }

    struct Target: Equatable {
        let app: String
        let windowID: String
        let tabID: String
    }

    static let browsers = [
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome"),
        Browser(name: "Brave Browser", bundleID: "com.brave.Browser"),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac"),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser")
    ]

    /// Called on the main thread.
    var onUpdate: ((Snapshot?, Target?) -> Void)?
    /// Called on the main thread when the browser rejects JavaScript from Apple Events.
    var onBlockedChange: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "id.sibergroup.neo.youtube", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var scripts: [String: NSAppleScript] = [:]
    private var target: Target?
    private var lastSnapshot: Snapshot?
    private var idleTicks = 0
    private var blocked = false

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 1.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    // MARK: - Controls

    func togglePlayPause() {
        control("(function(){var v=document.querySelector('video');if(v){if(v.paused){v.play();}else{v.pause();}}})()")
    }

    func pause() {
        control("(function(){var v=document.querySelector('video');if(v){v.pause();}})()")
    }

    func next() {
        control("(function(){var b=document.querySelector('.ytp-next-button, .next-button.ytmusic-player-bar');if(b){b.click();}})()")
    }

    func previous() {
        control("(function(){var b=document.querySelector('.previous-button.ytmusic-player-bar');var v=document.querySelector('video');if(b){b.click();}else if(v){v.currentTime=0;}})()")
    }

    func seek(to seconds: Double) {
        let value = String(format: "%.2f", max(seconds, 0))
        control("(function(){var v=document.querySelector('video');if(v){v.currentTime=\(value);}})()")
    }

    private func control(_ javascript: String) {
        queue.async { [weak self] in
            guard let self, let target = self.target else { return }
            let source = """
            tell application "\(target.app)"
                execute (tab id \(target.tabID) of window id \(target.windowID)) javascript "\(javascript)"
            end tell
            """
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            self.poll()
        }
    }

    // MARK: - Polling

    private var energyTicks = 0

    private func tick() {
        energyTicks += 1
        if EnergyMode.shared.shouldSkip(tick: energyTicks, factor: 3) { return }
        if lastSnapshot == nil {
            idleTicks += 1
            guard idleTicks % 3 == 0 else { return }
        } else {
            idleTicks = 0
        }
        poll()
    }

    private func poll() {
        let running = Self.browsers.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }

        var found: (Snapshot, Target)?
        var sawBlocked = false

        for browser in running {
            let outcome = read(browser)
            if outcome.blocked { sawBlocked = true }
            if let result = outcome.result {
                if found == nil || (found?.0.paused == true && !result.0.paused) {
                    found = result
                }
            }
        }

        let snapshot = found?.0
        let newTarget = found?.1
        let blockedNow = sawBlocked && found == nil
        let changed = snapshot != lastSnapshot || newTarget != target
        let blockedChanged = blockedNow != blocked

        lastSnapshot = snapshot
        target = newTarget
        blocked = blockedNow

        if changed || blockedChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if blockedChanged { self.onBlockedChange?(blockedNow) }
                if changed { self.onUpdate?(snapshot, newTarget) }
            }
        }
    }

    private func read(_ browser: Browser) -> (result: (Snapshot, Target)?, blocked: Bool) {
        let script: NSAppleScript
        if let cached = scripts[browser.name] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: Self.readScript(app: browser.name)) else { return (nil, false) }
            var compileError: NSDictionary?
            compiled.compileAndReturnError(&compileError)
            scripts[browser.name] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? ""
            return (nil, message.localizedCaseInsensitiveContains("JavaScript"))
        }

        guard let output = descriptor.stringValue, !output.isEmpty else { return (nil, false) }
        let parts = output.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let data = String(parts[2]).data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return (nil, false) }

        let target = Target(app: browser.name, windowID: String(parts[0]), tabID: String(parts[1]))
        return ((snapshot, target), false)
    }

    // MARK: - Scripts

    /// JavaScript reads metadata from the Media Session API (title, artist, artwork) and the video element.
    /// Intentionally avoids double quotes so it can be safely embedded in an AppleScript string.
    private static let readJS = "(function(){var v=document.querySelector('video');if(!v)return '';var m=navigator.mediaSession&&navigator.mediaSession.metadata;var id=new URLSearchParams(location.search).get('v')||'';var t=(m&&m.title)||document.title.replace(/ - YouTube( Music)?$/,'');var a=(m&&m.artist)||'';if(!a){var o=document.querySelector('#owner #channel-name a, ytd-channel-name a');if(o){a=o.textContent;}}var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}else if(id){art='https://i.ytimg.com/vi/'+id+'/hqdefault.jpg';}return JSON.stringify({title:(t||'').trim(),artist:(a||'').trim(),duration:isFinite(v.duration)?v.duration:0,position:v.currentTime||0,paused:v.paused,art:art,id:id||location.pathname});})()"

    private static func readScript(app: String) -> String {
        """
        tell application "\(app)"
            set fallback to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if u contains "youtube.com/watch" or u contains "music.youtube.com" then
                        set r to execute t javascript "\(readJS)"
                        if r is not missing value and r is not "" then
                            set entry to ((id of w) as string) & "|" & ((id of t) as string) & "|" & r
                            if r contains "\\"paused\\":false" then return entry
                            if fallback is "" then set fallback to entry
                        end if
                    end if
                end repeat
            end repeat
            return fallback
        end tell
        """
    }
}
