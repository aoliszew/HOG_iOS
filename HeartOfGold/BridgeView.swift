import SwiftUI

struct BridgeView: View {
    @EnvironmentObject var ship: ShipController

    private let amber = Color(red: 1.0, green: 0.72, blue: 0.2)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                velocityReadout
                if !ship.poweredUp {
                    modePicker
                    personalityPicker
                    briefingPickers
                    eventLog
                    if ship.resumableTrip != nil {
                        resumeButton
                    }
                    powerButton
                } else if ship.isPaused {
                    pausedScreen
                } else if !ship.activeChoices.isEmpty {
                    // A question is on the table: choices own the screen.
                    Spacer(minLength: 0)
                    choiceButtons
                    if ShipController.voiceInputEnabled {
                        talkButton
                    }
                } else {
                    personalityPicker
                    eventLog
                    if !ship.quickResponses.isEmpty {
                        quickResponseButtons
                    }
                    if !ship.pendingMessages.isEmpty {
                        playMessageButton
                    }
                    if ShipController.voiceInputEnabled {
                        talkButton
                    }
                    HStack(spacing: 12) {
                        pauseButton
                        powerButton
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

    // Driving-safe: huge stacked bars, glanceable at arm's length.
    private var choiceButtons: some View {
        VStack(spacing: 14) {
            Text("AWAITING ORDERS")
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.green)
            ForEach(ship.activeChoices, id: \.label) { choice in
                Button {
                    ship.choose(choice)
                } label: {
                    Text(choice.label.uppercased())
                        .font(.system(.title2, design: .monospaced).bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(amber)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(amber, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // Tap replies to the message that just played — big enough for a car mount.
    private var quickResponseButtons: some View {
        HStack(spacing: 10) {
            ForEach(ship.quickResponses, id: \.label) { response in
                Button {
                    ship.respond(response)
                } label: {
                    Text(response.label.uppercased())
                        .font(.system(.headline, design: .monospaced).bold())
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(amber)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(amber.opacity(0.7), lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // Primary in-flight control: full-width, thumb-sized from a car mount.
    private var talkButton: some View {
        Button {
            ship.listenForCommand()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ship.commands.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 30, weight: .bold))
                Text(ship.commands.isListening ? "LISTENING…" : "TALK TO SHIP")
                    .font(.system(.title3, design: .monospaced).bold())
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(ship.commands.isListening ? Color.green : Color.white.opacity(0.12))
            .foregroundStyle(ship.commands.isListening ? .black : amber)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(amber.opacity(0.5), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// Optional pre-flight mission briefing; skip it and the ship asks by voice.
    private var briefingPickers: some View {
        VStack(spacing: 8) {
            HStack {
                Text("STOPS")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.gray)
                    .frame(width: 54, alignment: .leading)
                Picker("Stops", selection: $ship.plan.plannedStops) {
                    Text("ASK").tag(Int?.none)
                    Text("0").tag(Int?.some(0))
                    Text("1").tag(Int?.some(1))
                    Text("2").tag(Int?.some(2))
                    Text("3+").tag(Int?.some(3))
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("LENGTH")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.gray)
                    .frame(width: 54, alignment: .leading)
                Picker("Length", selection: $ship.plan.length) {
                    Text("ASK").tag(TripPlan.Length?.none)
                    Text("QUICK").tag(TripPlan.Length?.some(.quickHop))
                    Text("<1 HR").tag(TripPlan.Length?.some(.underAnHour))
                    Text("LONG").tag(TripPlan.Length?.some(.longHaul))
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var pauseButton: some View {
        Button {
            ship.pauseMission()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 76)
                .frame(maxHeight: .infinity)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(amber)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var pausedScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("MISSION PAUSED")
                .font(.system(.title, design: .monospaced).bold())
                .foregroundStyle(amber)
            Text("All story clocks frozen. The universe will wait.\nIt has nowhere better to be.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                ship.resumeFromPause()
            } label: {
                Text("▶ RESUME")
                    .font(.system(.title3, design: .monospaced).bold())
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(Color.green.opacity(0.85))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            powerButton
        }
    }

    private var resumeButton: some View {
        Button {
            ship.resumeMission()
        } label: {
            Text(String(format: "⟳ RESUME MISSION (%.1f MI)", ship.resumableTrip?.distanceMiles ?? 0))
                .font(.system(.title3, design: .monospaced).bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.green.opacity(0.85))
                .foregroundStyle(.black)
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
