import SwiftUI

struct BridgeView: View {
    @EnvironmentObject var ship: ShipController

    private let amber = Color(red: 1.0, green: 0.72, blue: 0.2)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                velocityReadout
                modePicker
                personalityPicker
                eventLog
                if ship.poweredUp && !ship.activeChoices.isEmpty {
                    choiceButtons
                }
                if ship.poweredUp && !ship.pendingMessages.isEmpty {
                    playMessageButton
                }
                HStack(spacing: 12) {
                    powerButton
                    if ship.poweredUp {
                        talkButton
                    }
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("HEART OF GOLD")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(amber)
            Text(ship.poweredUp ? "● SYSTEMS ONLINE" : "○ SYSTEMS STANDBY")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ship.poweredUp ? .green : .gray)
        }
    }

    private var velocityReadout: some View {
        VStack(spacing: 2) {
            Text("SUBLIGHT VELOCITY")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.gray)
            Text(String(format: "%03.0f", ship.trip.speedMPH))
                .font(.system(size: 64, design: .monospaced).bold())
                .foregroundStyle(amber)
                .contentTransition(.numericText())
            Text(String(format: "MISSION DISTANCE  %.1f MI", ship.trip.distanceMiles))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber.opacity(0.4)))
    }

    private var modePicker: some View {
        Picker("Mode", selection: $ship.mode) {
            ForEach(TravelMode.allCases) { mode in
                Text(mode.rawValue.uppercased()).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(ship.poweredUp)
    }

    private var personalityPicker: some View {
        Picker("Engine", selection: $ship.personality) {
            ForEach(EnginePersonality.allCases) { p in
                Text(p.rawValue.uppercased()).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    private var eventLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ship.log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(entry.time, format: .dateTime.hour().minute())] \(entry.source)")
                            .font(.system(.caption2, design: .monospaced).bold())
                            .foregroundStyle(.green)
                        Text(entry.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(amber.opacity(0.9))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var choiceButtons: some View {
        HStack(spacing: 10) {
            ForEach(ship.activeChoices, id: \.label) { choice in
                Button {
                    ship.choose(choice)
                } label: {
                    Text(choice.label.uppercased())
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(amber)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(amber.opacity(0.6)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var playMessageButton: some View {
        Button {
            ship.playNextMessage()
        } label: {
            Text("▶ PLAY MESSAGE (\(ship.pendingMessages.count))")
                .font(.system(.headline, design: .monospaced).bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green.opacity(0.85))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var talkButton: some View {
        Button {
            ship.listenForCommand()
        } label: {
            Image(systemName: ship.commands.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 34))
                .frame(width: 72)
                .padding(.vertical, 12)
                .background(ship.commands.isListening ? Color.green : Color.white.opacity(0.12))
                .foregroundStyle(ship.commands.isListening ? .black : amber)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var powerButton: some View {
        Button {
            ship.poweredUp ? ship.powerDown() : ship.powerUp()
        } label: {
            Text(ship.poweredUp ? "POWER DOWN" : "POWER UP")
                .font(.system(.title3, design: .monospaced).bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(ship.poweredUp ? Color.red.opacity(0.8) : amber)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
