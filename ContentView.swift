import SwiftUI
import AVFoundation

struct ContentView: View {
    // Timer states
    @State private var timeRemaining = 25 * 60 // 25 minutes in seconds
    @State private var timerActive = false
    @State private var timerMode: TimerMode = .work
    @State private var completedPomodoros = 0
    @State private var showingSettings = false
    
    // Settings
    @AppStorage("workDuration") private var workDuration = 25
    @AppStorage("shortBreakDuration") private var shortBreakDuration = 5
    @AppStorage("longBreakDuration") private var longBreakDuration = 15
    @AppStorage("pomodorosUntilLongBreak") private var pomodorosUntilLongBreak = 4
    
    // Sound
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let soundPlayer = try? AVAudioPlayer(data: NSDataAsset(name: "bell")?.data ?? Data())
    
    // Computed properties
    var progress: Double {
        let totalTime = timerMode == .work ? workDuration * 60 :
                       (timerMode == .shortBreak ? shortBreakDuration * 60 : longBreakDuration * 60)
        return Double(totalTime - timeRemaining) / Double(totalTime)
    }
    
    // Background properties based on timer mode
    var backgroundGradient: LinearGradient {
        switch timerMode {
        case .work:
            return LinearGradient(
                gradient: Gradient(colors: [Color(#colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1)), Color(#colorLiteral(red: 0.9607843161, green: 0.7058823705, blue: 0.200000003, alpha: 1))]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .shortBreak:
            return LinearGradient(
                gradient: Gradient(colors: [Color(#colorLiteral(red: 0.4745098054, green: 0.8392156959, blue: 0.9764705896, alpha: 1)), Color(#colorLiteral(red: 0.5568627715, green: 0.3529411852, blue: 0.9686274529, alpha: 1))]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .longBreak:
            return LinearGradient(
                gradient: Gradient(colors: [Color(#colorLiteral(red: 0.3411764801, green: 0.6235294342, blue: 0.1686274558, alpha: 1)), Color(#colorLiteral(red: 0.1764705926, green: 0.4980392158, blue: 0.7568627596, alpha: 1))]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var textColor: Color {
        timerMode == .work ? .white : .white
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dynamic background
                backgroundGradient
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 1.0), value: timerMode)
                
                // Content
                VStack(spacing: 20) {
                    // Header with completed pomodoros
                    HStack {
                        ForEach(0..<pomodorosUntilLongBreak, id: \.self) { index in
                            Image(systemName: index < completedPomodoros % pomodorosUntilLongBreak ? "circle.fill" : "circle")
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .padding()
                    
                    // Timer mode indicator
                    Text(timerMode.rawValue)
                        .font(.title)
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                        .shadow(radius: 2)
                    
                    // Timer display
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 20)
                            .opacity(0.3)
                            .foregroundColor(.white)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                            .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                            .foregroundColor(.white)
                            .rotationEffect(Angle(degrees: 270))
                            .animation(.linear, value: progress)
                        
                        VStack {
                            Text("\(timeRemaining / 60):\(String(format: "%02d", timeRemaining % 60))")
                                .font(.system(size: 60, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                            
                            Text("\(timerMode == .work ? "Focus" : "Break")")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(radius: 1)
                        }
                    }
                    .padding(40)
                    
                    // Control buttons
                    HStack(spacing: 30) {
                        Button(action: {
                            timerActive.toggle()
                        }) {
                            Image(systemName: timerActive ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                        
                        Button(action: resetTimer) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                    }
                    
                    // Skip button
                    Button(action: skipToNextPhase) {
                        Text("Skip to next phase")
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                            .padding()
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                }
                .padding()
            }
            .navigationTitle("Pomo-Pulse")
            .preferredColorScheme(timerMode == .work ? .dark : .light)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gear")
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    workDuration: $workDuration,
                    shortBreakDuration: $shortBreakDuration,
                    longBreakDuration: $longBreakDuration,
                    pomodorosUntilLongBreak: $pomodorosUntilLongBreak
                )
            }
        }
        .onReceive(timer) { _ in
            if timerActive && timeRemaining > 0 {
                timeRemaining -= 1
            } else if timerActive && timeRemaining == 0 {
                playSound()
                moveToNextPhase()
            }
        }
    }
    
    // Timer control functions
    func resetTimer() {
        timerActive = false
        updateTimeRemainingForCurrentMode()
    }
    
    func playSound() {
        soundPlayer?.play()
    }
    
    func moveToNextPhase() {
        timerActive = false
        
        if timerMode == .work {
            completedPomodoros += 1
            if completedPomodoros % pomodorosUntilLongBreak == 0 {
                timerMode = .longBreak
            } else {
                timerMode = .shortBreak
            }
        } else {
            timerMode = .work
        }
        
        updateTimeRemainingForCurrentMode()
    }
    
    func skipToNextPhase() {
        moveToNextPhase()
    }
    
    func updateTimeRemainingForCurrentMode() {
        switch timerMode {
        case .work:
            timeRemaining = workDuration * 60
        case .shortBreak:
            timeRemaining = shortBreakDuration * 60
        case .longBreak:
            timeRemaining = longBreakDuration * 60
        }
    }
}

// Timer mode enum
enum TimerMode: String {
    case work = "Work"
    case shortBreak = "Short Break"
    case longBreak = "Long Break"
}

// Settings view
struct SettingsView: View {
    @Binding var workDuration: Int
    @Binding var shortBreakDuration: Int
    @Binding var longBreakDuration: Int
    @Binding var pomodorosUntilLongBreak: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Timer Durations")) {
                    Stepper("Work: \(workDuration) minutes", value: $workDuration, in: 1...60)
                    Stepper("Short Break: \(shortBreakDuration) minutes", value: $shortBreakDuration, in: 1...30)
                    Stepper("Long Break: \(longBreakDuration) minutes", value: $longBreakDuration, in: 5...60)
                }
                
                Section(header: Text("Pomodoro Sequence")) {
                    Stepper("Pomodoros until long break: \(pomodorosUntilLongBreak)", value: $pomodorosUntilLongBreak, in: 1...10)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@main
struct PomoPulseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
