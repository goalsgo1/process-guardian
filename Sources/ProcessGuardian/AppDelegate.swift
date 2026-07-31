import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var viewModel: CleanupViewModel!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 없이 메뉴바에만 상주
        NSApp.setActivationPolicy(.accessory)

        viewModel = CleanupViewModel()
        viewModel.refreshDiskStatus()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItemTitle()

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 480)
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.viewModel.refreshDiskStatus()
            self?.updateStatusItemTitle()
        }

        NSApp.activate(ignoringOtherApps: true)

        // NSPopover는 "생애 첫 show()" 호출에서만 내부 윈도우 위치 계산을 잘못하는
        // 고질적인 버그가 있음 (activate 타이밍과 무관, 두 번째 show부터는 항상 정상).
        // 그래서 사용자가 실제로 클릭하기 전에, 안 보이게 한 번 show+close로
        // "가짜 첫 클릭"을 미리 소진시켜서 실제 첫 클릭이 내부적으로 두 번째가 되게 한다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.warmUpPopover()
        }
    }

    private func warmUpPopover() {
        guard let button = statusItem.button else { return }
        let animatesBefore = popover.animates
        popover.animates = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.performClose(nil)
        popover.animates = animatesBefore
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button, let status = DiskMonitor.currentStatus() else { return }
        let color: NSColor
        switch status.level {
        case .red: color = .systemRed
        case .yellow: color = .systemYellow
        case .green: color = .systemGreen
        }
        let freeGB = Double(status.freeBytes) / 1_073_741_824
        let text = String(format: "%d%% · 여유 %.1fGB", status.usedPercent, freeGB)
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color, .font: NSFont.menuBarFont(ofSize: 13)]
        )
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ProcessGuardian 종료", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // 다음 왼쪽 클릭은 다시 팝오버가 뜨도록, 메뉴를 보여준 직후 바로 떼어낸다.
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            viewModel.refreshDiskStatus()
            updateStatusItemTitle()
            // 활성화를 먼저 해야 팝오버 위치 계산이 올바른 앱 활성 상태 기준으로 이뤄짐.
            // 순서가 반대면 최초 1회는 잘못된 위치에 뜨고, 활성화 이후부터 정상 위치로 뜸.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
