//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import AVFAudio
import KeyboardShortcuts
import ScreenCaptureKit

extension AppDelegate {
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")]
            as? CGDirectDisplayID
    }
}
