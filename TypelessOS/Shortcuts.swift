//
//  Shortcuts.swift
//  TypelessOS
//
//  Created by Martin Persson on 2024-08-11.
//

import AppKit
import KeyboardShortcuts
import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        KeyboardShortcuts.onKeyDown(for: .recordSystemAudio) { [self] in
            Task { await toggleRecording(type: "audio") }
        }
        // KeyboardShortcuts.onKeyDown(for: .recordCurrentDisplay) { [self] in
        //     Task { await toggleRecording(type: "display") }
        // }
        // KeyboardShortcuts.onKeyDown(for: .recordCurrentWindow) { [self] in
        //     Task { await toggleRecording(type: "window") }
        // }
    }

    func toggleRecording(type: String) async {
        // TODO::
    }
}

extension AppDelegate {
    func allowShortcuts(_ allow: Bool) {
        if allow {
            KeyboardShortcuts.enable(.recordCurrentDisplay, .recordCurrentWindow, .recordSystemAudio)
        } else {
            KeyboardShortcuts.disable(.recordCurrentDisplay, .recordCurrentWindow, .recordSystemAudio)
        }
    }
}
