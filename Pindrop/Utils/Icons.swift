//
//  Icons.swift
//  Pindrop
//

import SwiftUI

enum Icon: String {
    case mic = "icon-mic"
    case micOff = "icon-mic-off"
    case record = "icon-record"
    case waveform = "icon-waveform"
    
    case settings = "icon-settings"
    case keyboard = "icon-keyboard"
    case cpu = "icon-cpu"
    case sparkles = "icon-sparkles"
    
    case clipboard = "icon-clipboard"
    case textCursor = "icon-text-cursor"
    
    case window = "icon-window"
    case reset = "icon-reset"
    case clock = "icon-clock"
    case history = "icon-history"
    case search = "icon-search"
    
    case export = "icon-export"
    case fileText = "icon-file-text"
    case json = "icon-json"
    case table = "icon-table"
    case copy = "icon-copy"
    
    case check = "icon-check"
    case warning = "icon-warning"
    case shield = "icon-shield"
    case info = "icon-info"
    case loading = "icon-loading"
    
    case eye = "icon-eye"
    case eyeOff = "icon-eye-off"
    
    case chevronLeft = "icon-chevron-left"
    case chevronRight = "icon-chevron-right"
    case arrowRight = "icon-arrow-right"
    case arrowDown = "icon-arrow-down"
    case download = "icon-download"
    
    case hand = "icon-hand"
    case construction = "icon-construction"
    case close = "icon-close"
    case server = "icon-server"
    case router = "icon-router"
    case hardDrive = "icon-hard-drive"
    case zap = "icon-zap"
    case target = "icon-target"
    case accessibility = "icon-accessibility"
    case lock = "icon-lock"
    case circle = "icon-circle"
    case circleCheck = "icon-circle-check"
    case circleDot = "icon-circle-dot"
    
    case openai = "icon-openai"
    case anthropic = "icon-anthropic"
    case google = "icon-google"
    case openrouter = "icon-openrouter"
    
    case circleX = "icon-circle-x"
    case stickyNote = "icon-sticky-note"
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 16
    
    var body: some View {
        Image(icon.rawValue)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
