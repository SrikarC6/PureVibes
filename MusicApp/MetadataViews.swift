//
//  MetadataViews.swift
//  MusicPlayer - Enhanced UI Components
//
//  Components for displaying track metadata, format info, and quality indicators
//

import SwiftUI

// MARK: - Metadata Badge (Enhanced)
struct MetadataBadge: View {
    let text: String
    let icon: String
    let color: Color
    let style: BadgeStyle
    
    enum BadgeStyle {
        case filled
        case outlined
        case minimal
    }
    
    init(text: String, icon: String, color: Color, style: BadgeStyle = .filled) {
        self.text = text
        self.icon = icon
        self.color = color
        self.style = style
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .overlay(
            style == .outlined ? 
                Capsule().strokeBorder(color, lineWidth: 1.5) : nil
        )
        .clipShape(Capsule())
    }
    
    private var foregroundColor: Color {
        switch style {
        case .filled: return .white
        case .outlined, .minimal: return color
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .filled: return color
        case .outlined: return color.opacity(0.1)
        case .minimal: return color.opacity(0.15)
        }
    }
}

// MARK: - Advisory Badge (Apple Music Style)
struct AdvisoryBadge: View {
    let advisory: String
    
    var body: some View {
        ZStack {
            if advisory == "Explicit" {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.9, green: 0.2, blue: 0.3))
                    .frame(width: 16, height: 16)
                Text("E")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                Text("C")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Apple Digital Master Badge
struct AppleDigitalMasterBadge: View {
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
            if !compact {
                Text("Apple Digital Master")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.5, blue: 1.0),
                    Color(red: 0.4, green: 0.6, blue: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Quality Tier Indicator
struct QualityTierBadge: View {
    let tier: Track.QualityTier
    let showLabel: Bool
    
    init(tier: Track.QualityTier, showLabel: Bool = true) {
        self.tier = tier
        self.showLabel = showLabel
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tier.color)
                .frame(width: 8, height: 8)
            
            if showLabel {
                Text(tier.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tier.color)
            }
        }
        .padding(.horizontal, showLabel ? 8 : 6)
        .padding(.vertical, 4)
        .background(tier.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Format Information Panel
struct FormatInfoPanel: View {
    let track: Track
    let compact: Bool
    
    init(track: Track, compact: Bool = false) {
        self.track = track
        self.compact = compact
    }
    
    var body: some View {
        if compact {
            compactView
        } else {
            expandedView
        }
    }
    
    private var compactView: some View {
        HStack(spacing: 6) {
            if let format = track.fileFormat {
                Text(format)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            if let bitrate = track.bitrate {
                Text("•")
                    .foregroundColor(.secondary.opacity(0.5))
                Text("\(bitrate) kbps")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            if let sampleRate = track.sampleRate {
                Text("•")
                    .foregroundColor(.secondary.opacity(0.5))
                Text("\(Int(sampleRate/1000)) kHz")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Format")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                if let format = track.fileFormat, let codec = track.codec {
                    FormatInfoRow(label: "Format", value: "\(format) (\(codec))")
                }
                
                if let bitrate = track.bitrate {
                    FormatInfoRow(label: "Bitrate", value: "\(bitrate) kbps")
                }
                
                if let sampleRate = track.sampleRate {
                    FormatInfoRow(label: "Sample Rate", value: String(format: "%.1f kHz", sampleRate / 1000))
                }
                
                if let bitDepth = track.bitDepth, bitDepth > 0 {
                    FormatInfoRow(label: "Bit Depth", value: "\(bitDepth)-bit")
                }
                
                if let channels = track.channels {
                    let channelText = channels == 2 ? "Stereo" : channels == 1 ? "Mono" : "\(channels) channels"
                    FormatInfoRow(label: "Channels", value: channelText)
                }
                
                if let fileSize = track.fileSizeString {
                    FormatInfoRow(label: "File Size", value: fileSize)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
        }
    }
}

struct FormatInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Track List Row (Enhanced)
struct TrackListRow: View {
    let track: Track
    let isSelected: Bool
    var isPlaying: Bool = false // Added support for Playing state
    let artwork: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Artwork Thumbnail
            if let artwork = artwork {
                ZStack {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(isPlaying ? 0.6 : 1.0)
                    
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                    Image(systemName: "music.note")
                        .foregroundColor(.gray.opacity(0.5))
                    
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .frame(width: 44, height: 44)
            }
            
            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 13, weight: isPlaying ? .bold : .medium))
                    .lineLimit(1)
                    .foregroundColor(isPlaying ? .accentColor : (isSelected ? .primary : .primary.opacity(0.9)))
                
                Text(track.artist)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                
                // Compact badges
                HStack(spacing: 6) {
                    if track.isAppleDigitalMaster {
                        Image(systemName: "hifispeaker.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                    }
                    
                    if let advisory = track.itunesAdvisory {
                        AdvisoryBadge(advisory: advisory)
                            .scaleEffect(0.8)
                    }
                    
                    QualityTierBadge(tier: track.qualityTier, showLabel: false)
                        .scaleEffect(0.9)
                    
                    if let format = track.fileFormat {
                        Text(format)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            // Duration
            if let duration = track.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(8)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}