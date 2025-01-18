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
    @objc func prepRecord(_ sender: NSMenuItem) {
        // TODO::
    }

    @objc func stopCountdown() { CountdownManager.shared.finishCountdown(startRecording: false) }
    @objc func skipCountdown() { CountdownManager.shared.finishCountdown(startRecording: true) }

    func record(audioOnly: Bool, filter: SCContentFilter) async {
        var conf = SCStreamConfiguration()
        if #available(macOS 15.0, *), !audioOnly {
            if await ud.bool(forKey: Preferences.kEnableHDR) {
                conf = SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
            }
            conf.captureMicrophone = await ud.bool(forKey: Preferences.kRecordMic) && !audioOnly
        }

        conf.width = 2
        conf.height = 2

        conf.queueDepth = 5  // ensure higher fps at the expense of some memory
        conf.minimumFrameInterval = await CMTime(
            value: 1,
            timescale: audioOnly
                ? CMTimeScale.max : CMTimeScale(ud.integer(forKey: Preferences.kFrameRate)))
        conf.showsCursor = await ud.bool(forKey: Preferences.kShowMouse)
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        startRecording: do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if #available(macOS 15.0, *), conf.captureMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global())
            }

            startTime = Date.now

            try await stream.startCapture()
            allowShortcuts(true)
        } catch {
            alertRecordingFailure(error)
            stream = nil
            stopRecording(withError: true)
            return
        }

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }
    }

    @objc func stopRecording(withError: Bool = false) {
        DispatchQueue.main.async { [self] in
            statusItem.menu = nil

            if stream != nil {
                stream.stopCapture()
                stream = nil
            }

            if useSystemRecorder {
                recordingOutput = nil
            } else {
                startTime = nil
            }
            streamType = nil
            audioFile = nil  // close audio file
            window = nil
            screen = nil

            updateTimer?.invalidate()

            updateIcon()
            createMenu()

            if !withError {
                allowShortcuts(true)
                copyToClipboard([NSURL(fileURLWithPath: filePath)])
            }
        }
    }

    func updateAudioSettings() {
        audioSettings = [AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2]  // reset audioSettings
        switch ud.string(forKey: Preferences.kAudioFormat) {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =
                ud.integer(forKey: Preferences.kAudioQuality) * 1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] =
                ud.string(forKey: Preferences.kAudioFormat) != VideoFormat.mp4.rawValue
                ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =
                ud.integer(forKey: Preferences.kAudioQuality) * 1000
        default:
            assertionFailure(
                "unknown audio format while setting audio settings: ".local
                    + (ud.string(forKey: Preferences.kAudioFormat) ?? "[no defaults]".local))
        }
    }

    func getFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        var fileName = ud.string(forKey: Preferences.kFileName)
        if fileName == nil || fileName!.isEmpty {
            fileName = "Recording at %t".local
        }
        // bit of a magic number but worst case ".flac" is 5 characters on top of this..
        let fileNameWithDates = fileName!.replacingOccurrences(
            of: "%t", with: dateFormatter.string(from: Date())
        ).prefix(Int(NAME_MAX) - 5)

        let saveDirectory = ud.string(forKey: Preferences.kSaveDirectory)
        // ensure the destination folder exists
        do {
            try FileManager.default.createDirectory(
                atPath: saveDirectory!, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create destination folder: ".local + error.localizedDescription)
        }

        return saveDirectory! + "/" + fileNameWithDates
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        //if self.streamType == nil { self.startTime = nil }
        if !useSystemRecorder || streamType == .systemaudio {
            return formatter.string(from: Date.now.timeIntervalSince(startTime ?? Date.now))
                ?? "Unknown".local
        } else if #available(macOS 15, *) {
            if let recOut = (recordingOutput as? SCRecordingOutput) {
                if recOut.recordedDuration.seconds.isNaN { return "00:00" }
                return formatter.string(from: recOut.recordedDuration.seconds) ?? "Unknown".local
            }
        }
        return "--:--"
    }

    func getRecordingSize() -> String {
        let byteFormat = ByteCountFormatter()
        byteFormat.allowedUnits = [.useMB]
        byteFormat.countStyle = .file
        if !useSystemRecorder || streamType == .systemaudio {
            do {
                if let filePath = filePath {
                    let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
                    return byteFormat.string(
                        fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
                }
            } catch {
                print(
                    String(
                        format: "failed to fetch file for size indicator: %@".local,
                        error.localizedDescription))
            }
        } else if #available(macOS 15, *), let recOut = (recordingOutput as? SCRecordingOutput) {
            return byteFormat.string(fromByteCount: Int64(recOut.recordedFileSize))
        }
        return "Unknown".local
    }

    func alertRecordingFailure(_ error: Error) {
        allowShortcuts(false)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Capture failed!".local
            alert.informativeText = String(
                format:
                    "Couldn't start the recording:\n“%@”\n\nIt is possible that the recording settings, such as HDR or the encoder, are not compatible with your device.\n\nPlease check Azayaka's preferences."
                    .local, error.localizedDescription)
            alert.addButton(withTitle: "Okay".local)
            alert.alertStyle = .critical
            alert.runModal()
            self.allowShortcuts(true)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")]
            as? CGDirectDisplayID
    }
}
