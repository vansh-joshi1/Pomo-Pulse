import SwiftUI
import AVFoundation
import AuthenticationServices
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// Firebase configuration setup
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

// Model for storing completed session data
struct PomodoroSession: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var duration: Int // in minutes
    var type: String // "Work", "Short Break", or "Long Break"
    var userId: String? // For linking sessions to user accounts
    
    // Computed property for formatted date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// User Profile Model
struct UserProfile: Codable {
    var userId: String
    var email: String
    var displayName: String?
    var emailNotificationsEnabled: Bool = true
    var emailFrequency: EmailFrequency = .weekly
    var lastEmailSent: Date?
    
    enum EmailFrequency: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }
}

// Authentication Manager
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var db = Firestore.firestore()
    
    init() {
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        if let user = Auth.auth().currentUser {
            self.isAuthenticated = true
            self.loadUserProfile(userId: user.uid)
        } else {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    func loadUserProfile(userId: String) {
        self.isLoading = true
        
        db.collection("users").document(userId).getDocument { [weak self] document, error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = "Failed to load profile: \(error.localizedDescription)"
                return
            }
            
            if let document = document, document.exists,
               let data = try? document.data(as: UserProfile.self) {
                self?.currentUser = data
            } else {
                // Create new profile if it doesn't exist
                if let user = Auth.auth().currentUser {
                    let newProfile = UserProfile(
                        userId: user.uid,
                        email: user.email ?? "",
                        displayName: user.displayName
                    )
                    
                    try? self?.db.collection("users").document(user.uid).setData(from: newProfile)
                    self?.currentUser = newProfile
                }
            }
        }
    }
    
    func signInWithEmail(email: String, password: String, completion: @escaping (Bool) -> Void) {
        self.isLoading = true
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] authResult, error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = error.localizedDescription
                completion(false)
                return
            }
            
            if let user = authResult?.user {
                self?.isAuthenticated = true
                self?.loadUserProfile(userId: user.uid)
                completion(true)
            } else {
                self?.errorMessage = "Unknown error occurred"
                completion(false)
            }
        }
    }
    
    func signUpWithEmail(email: String, password: String, name: String, completion: @escaping (Bool) -> Void) {
        self.isLoading = true
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] authResult, error in
            if let error = error {
                self?.isLoading = false
                self?.errorMessage = error.localizedDescription
                completion(false)
                return
            }
            
            if let user = authResult?.user {
                // Update display name
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = name
                changeRequest.commitChanges { _ in }
                
                // Create user profile
                let newProfile = UserProfile(
                    userId: user.uid,
                    email: email,
                    displayName: name
                )
                
                try? self?.db.collection("users").document(user.uid).setData(from: newProfile)
                
                self?.isAuthenticated = true
                self?.currentUser = newProfile
                self?.isLoading = false
                completion(true)
            } else {
                self?.isLoading = false
                self?.errorMessage = "Unknown error occurred"
                completion(false)
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.isAuthenticated = false
            self.currentUser = nil
        } catch {
            self.errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    func updateEmailPreferences(enabled: Bool, frequency: UserProfile.EmailFrequency, completion: @escaping (Bool) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        
        self.isLoading = true
        
        db.collection("users").document(userId).updateData([
            "emailNotificationsEnabled": enabled,
            "emailFrequency": frequency.rawValue
        ]) { [weak self] error in
            self?.isLoading = false
            
            if let error = error {
                self?.errorMessage = "Failed to update preferences: \(error.localizedDescription)"
                completion(false)
                return
            }
            
            if let currentUser = self?.currentUser {
                var updatedUser = currentUser
                updatedUser.emailNotificationsEnabled = enabled
                updatedUser.emailFrequency = frequency
                self?.currentUser = updatedUser
            }
            
            completion(true)
        }
    }
}

// Session History Manager with Cloud Sync
class SessionHistoryManager: ObservableObject {
    private let localHistoryKey = "pomodoroSessionHistory"
    private var db = Firestore.firestore()
    @Published var sessions: [PomodoroSession] = []
    
    // Load sessions from both local storage and cloud
    func loadSessions(for userId: String? = nil) -> [PomodoroSession] {
        var localSessions: [PomodoroSession] = []
        
        // Load from local storage first
        if let data = UserDefaults.standard.data(forKey: localHistoryKey),
           let decoded = try? JSONDecoder().decode([PomodoroSession].self, from: data) {
            localSessions = decoded
        }
        
        // If user is logged in, sync with cloud
        if let userId = userId {
            syncSessionsWithCloud(localSessions: localSessions, userId: userId)
        }
        
        return localSessions
    }
    
    // Sync local sessions with cloud
    func syncSessionsWithCloud(localSessions: [PomodoroSession], userId: String) {
        // Get cloud sessions
        db.collection("users").document(userId).collection("sessions").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("Error getting cloud sessions: \(error)")
                return
            }
            
            guard let snapshot = snapshot else { return }
            
            // Convert cloud documents to sessions
            var cloudSessions: [PomodoroSession] = []
            for document in snapshot.documents {
                if let session = try? document.data(as: PomodoroSession.self) {
                    cloudSessions.append(session)
                }
            }
            
            // Merge local and cloud sessions
            var mergedSessions = localSessions
            
            // Add cloud sessions that don't exist locally
            for cloudSession in cloudSessions {
                if !localSessions.contains(where: { $0.id == cloudSession.id }) {
                    mergedSessions.append(cloudSession)
                }
            }
            
            // Update local storage with merged sessions
            self?.sessions = mergedSessions
            self?.saveSessions(mergedSessions)
            
            // Upload local sessions that don't exist in cloud
            for localSession in localSessions {
                if !cloudSessions.contains(where: { $0.id == localSession.id }) {
                    var sessionWithUserId = localSession
                    sessionWithUserId.userId = userId
                    
                    do {
                        try self?.db.collection("users").document(userId)
                            .collection("sessions")
                            .document(localSession.id.uuidString)
                            .setData(from: sessionWithUserId)
                    } catch {
                        print("Error uploading session: \(error)")
                    }
                }
            }
        }
    }
    
    // Save sessions locally
    func saveSessions(_ sessions: [PomodoroSession]) {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: localHistoryKey)
        }
        self.sessions = sessions
    }
    
    // Add a new session both locally and to cloud if user is logged in
    func addSession(_ session: PomodoroSession, to sessions: inout [PomodoroSession], userId: String? = nil) {
        var sessionToAdd = session
        sessionToAdd.userId = userId
        
        sessions.append(sessionToAdd)
        saveSessions(sessions)
        
        // If user is logged in, also save to cloud
        if let userId = userId {
            do {
                try db.collection("users").document(userId)
                    .collection("sessions")
                    .document(session.id.uuidString)
                    .setData(from: sessionToAdd)
            } catch {
                print("Error saving session to cloud: \(error)")
            }
        }
    }
    
    // Delete session both locally and from cloud
    func deleteSession(at indexSet: IndexSet, from sessions: inout [PomodoroSession], userId: String? = nil) {
        let sessionsToDelete = indexSet.map { sessions[$0] }
        
        // Remove from local storage
        sessions.remove(atOffsets: indexSet)
        saveSessions(sessions)
        
        // Remove from cloud if user is logged in
        if let userId = userId {
            for session in sessionsToDelete {
                db.collection("users").document(userId)
                    .collection("sessions")
                    .document(session.id.uuidString)
                    .delete()
            }
        }
    }
    
    // Generate email content for user's session summary
    func generateEmailContent(for sessions: [PomodoroSession], period: String) -> String {
        let workSessions = sessions.filter { $0.type == "Work" }
        let totalWorkMinutes = workSessions.reduce(0) { $0 + $1.duration }
        let totalWorkSessions = workSessions.count
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        var emailContent = """
        <html>
        <body>
        <h1>Your Pomo-Pulse \(period) Summary</h1>
        <p>Here's how you've been doing with your Pomodoro sessions:</p>
        
        <div style="background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin: 15px 0;">
            <h2>Summary</h2>
            <p>Total focus sessions: <strong>\(totalWorkSessions)</strong></p>
            <p>Total focus time: <strong>\(totalWorkMinutes) minutes</strong></p>
            <p>That's approximately <strong>\(totalWorkMinutes / 60) hours and \(totalWorkMinutes % 60) minutes</strong> of focused work!</p>
        </div>
        
        <h2>Recent Sessions</h2>
        <table style="width: 100%; border-collapse: collapse;">
            <tr style="background-color: #4CAF50; color: white;">
                <th style="padding: 8px; text-align: left;">Date</th>
                <th style="padding: 8px; text-align: left;">Type</th>
                <th style="padding: 8px; text-align: left;">Duration</th>
            </tr>
        """
        
        // Add up to 10 most recent work sessions
        let recentSessions = workSessions.sorted { $0.date > $1.date }.prefix(10)
        for (index, session) in recentSessions.enumerated() {
            let backgroundColor = index % 2 == 0 ? "#f2f2f2" : "white"
            emailContent += """
            <tr style="background-color: \(backgroundColor);">
                <td style="padding: 8px;">\(session.formattedDate)</td>
                <td style="padding: 8px;">\(session.type)</td>
                <td style="padding: 8px;">\(session.duration) minutes</td>
            </tr>
            """
        }
        
        emailContent += """
        </table>
        
        <div style="margin-top: 20px; padding: 10px; background-color: #e8f5e9; border-radius: 5px;">
            <p>Keep up the good work! Regular focused sessions lead to better productivity and results.</p>
            <p>This email was sent from the Pomo-Pulse app. You can change your email preferences in the app settings.</p>
        </div>
        </body>
        </html>
        """
        
        return emailContent
    }
    
    // Trigger email sending
    func sendEmailUpdate(for user: UserProfile, sessions: [PomodoroSession]) {
        // In a real app, you would call a cloud function or backend API here
        // For this demo, we'll simulate the email sending with a cloud function trigger
        
        let now = Date()
        let calendar = Calendar.current
        
        // Filter sessions based on frequency
        var periodSessions: [PomodoroSession] = []
        var period = ""
        
        switch user.emailFrequency {
        case .daily:
            let startOfDay = calendar.startOfDay(for: now)
            periodSessions = sessions.filter { $0.date >= startOfDay }
            period = "Daily"
        case .weekly:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            periodSessions = sessions.filter { $0.date >= startOfWeek }
            period = "Weekly"
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components)!
            periodSessions = sessions.filter { $0.date >= startOfMonth }
            period = "Monthly"
        }
        
        // Generate email content
        let emailContent = generateEmailContent(for: periodSessions, period: period)
        
        // In a real app, this would trigger a cloud function or backend API call
        // For demonstration, we'll simulate sending by updating the lastEmailSent date
        let userId = user.userId
        db.collection("users").document(userId).updateData([
            "lastEmailSent": Timestamp(date: now)
        ])
        
        // Print the email content for demo purposes
        print("Email would be sent to \(user.email) with content: \(emailContent)")
    }
}

struct ContentView: View {
    // Authentication
    @StateObject private var authManager = AuthManager()
    @State private var showingLoginView = false
    @State private var showingSignupView = false
    
    // Timer states
    @State private var timeRemaining = 25 * 60 // 25 minutes in seconds
    @State private var timerActive = false
    @State private var timerMode: TimerMode = .work
    @State private var completedPomodoros = 0
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingProfile = false
    
    // Session history
    @StateObject private var historyManager = SessionHistoryManager()
    @State private var sessionHistory: [PomodoroSession] = []
    
    // For tracking session start time
    @State private var sessionStartTime = Date()
    
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
                    // Header with completed pomodoros and user profile
                    HStack {
                        // Pomodoro indicators
                        HStack {
                            ForEach(0..<pomodorosUntilLongBreak, id: \.self) { index in
                                Image(systemName: index < completedPomodoros % pomodorosUntilLongBreak ? "circle.fill" : "circle")
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                        }
                        .padding()
                        
                        Spacer()
                        
                        // User profile button
                        Button(action: {
                            if authManager.isAuthenticated {
                                showingProfile = true
                            } else {
                                showingLoginView = true
                            }
                        }) {
                            Image(systemName: authManager.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .padding(.trailing)
                    }
                    
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
                            if !timerActive {
                                // Start timer and record start time
                                sessionStartTime = Date()
                            }
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
                    
                    // Skip and History buttons
                    HStack(spacing: 20) {
                        Button(action: skipToNextPhase) {
                            Text("Skip")
                                .foregroundColor(.white)
                                .shadow(radius: 1)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        
                        Button(action: { showingHistory.toggle() }) {
                            Text("History")
                                .foregroundColor(.white)
                                .shadow(radius: 1)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
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
            .sheet(isPresented: $showingHistory) {
                HistoryView(
                    sessions: $sessionHistory,
                    historyManager: historyManager,
                    userId: authManager.currentUser?.userId
                )
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView(authManager: authManager)
            }
            .sheet(isPresented: $showingLoginView) {
                AuthView(authManager: authManager, isSignUp: false)
            }
            .sheet(isPresented: $showingSignupView) {
                AuthView(authManager: authManager, isSignUp: true)
            }
            .onReceive(timer) { _ in
                if timerActive && timeRemaining > 0 {
                    timeRemaining -= 1
                } else if timerActive && timeRemaining == 0 {
                    playSound()
                    recordCompletedSession()
                    moveToNextPhase()
                }
            }
            .onAppear {
                // Load session history when app launches
                sessionHistory = historyManager.loadSessions(for: authManager.currentUser?.userId)
            }
            .onChange(of: authManager.isAuthenticated) {
                if authManager.isAuthenticated {
                    sessionHistory = historyManager.loadSessions(for: authManager.currentUser?.userId)
                }
            }

        }
    }
    
    // Record completed session
    func recordCompletedSession() {
        let sessionDuration: Int
        switch timerMode {
        case .work:
            sessionDuration = workDuration
        case .shortBreak:
            sessionDuration = shortBreakDuration
        case .longBreak:
            sessionDuration = longBreakDuration
        }
        
        let session = PomodoroSession(
            date: sessionStartTime,
            duration: sessionDuration,
            type: timerMode.rawValue
        )
        
        historyManager.addSession(
            session,
            to: &sessionHistory,
            userId: authManager.currentUser?.userId
        )
        
        // Check if we should send an email update
        if let user = authManager.currentUser, user.emailNotificationsEnabled {
            var shouldSendEmail = false
            
            if let lastSent = user.lastEmailSent {
                let calendar = Calendar.current
                let now = Date()
                
                switch user.emailFrequency {
                case .daily:
                    shouldSendEmail = !calendar.isDate(lastSent, inSameDayAs: now)
                case .weekly:
                    let weekOfYear = calendar.component(.weekOfYear, from: now)
                    let lastWeekOfYear = calendar.component(.weekOfYear, from: lastSent)
                    shouldSendEmail = weekOfYear != lastWeekOfYear
                case .monthly:
                    let month = calendar.component(.month, from: now)
                    let lastMonth = calendar.component(.month, from: lastSent)
                    shouldSendEmail = month != lastMonth
                }
            } else {
                // No emails sent yet
                shouldSendEmail = true
            }
            
            if shouldSendEmail {
                historyManager.sendEmailUpdate(for: user, sessions: sessionHistory)
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
        // Only record if timer was active
        if timerActive {
            recordCompletedSession()
        }
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

// History view - Completing the implementation
struct HistoryView: View {
    @Binding var sessions: [PomodoroSession]
    @ObservedObject var historyManager: SessionHistoryManager
    var userId: String?
    @Environment(\.dismiss) var dismiss
    @State private var selectedFilter: SessionFilter = .all
    
    enum SessionFilter: String, CaseIterable {
        case all = "All"
        case work = "Work"
        case breaks = "Breaks"
    }
    
    var filteredSessions: [PomodoroSession] {
        switch selectedFilter {
        case .all:
            return sessions
        case .work:
            return sessions.filter { $0.type == "Work" }
        case .breaks:
            return sessions.filter { $0.type == "Short Break" || $0.type == "Long Break" }
        }
    }
    
    var body: some View {
            NavigationView {
                VStack {
                    // Filter selector
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(SessionFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    // Sessions list
                    List {
                        ForEach(filteredSessions.sorted(by: { $0.date > $1.date })) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(session.type)
                                        .font(.headline)
                                        .foregroundColor(session.type == "Work" ? .red : .green)
                                    Spacer()
                                    Text("\(session.duration) min")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text(session.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            let indicesToDelete = indexSet.map { filteredSessions.sorted(by: { $0.date > $1.date })[$0].id }
                            let allSessionsIndices = IndexSet(indicesToDelete.compactMap { id in
                                sessions.firstIndex(where: { $0.id == id })
                            })
                            historyManager.deleteSession(at: allSessionsIndices, from: &sessions, userId: userId)
                        }
                    }
                    
                    // Stats summary
                    VStack(spacing: 10) {
                        let workSessions = sessions.filter { $0.type == "Work" }
                        let totalWorkMinutes = workSessions.reduce(0) { $0 + $1.duration }
                        let totalSessions = workSessions.count
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Total Focus Time")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(totalWorkMinutes) min")
                                    .font(.headline)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Focus Sessions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(totalSessions)")
                                    .font(.headline)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 1)
                    .padding(.horizontal)
                }
                .navigationTitle("Session History")
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

    // Authentication Views
    struct AuthView: View {
        @ObservedObject var authManager: AuthManager
        var isSignUp: Bool
        @Environment(\.dismiss) var dismiss
        
        @State private var email = ""
        @State private var password = ""
        @State private var name = ""
        @State private var showingAlert = false
        
        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Account Details")) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        SecureField("Password", text: $password)
                        
                        if isSignUp {
                            TextField("Display Name", text: $name)
                        }
                    }
                    
                    Section {
                        Button(isSignUp ? "Create Account" : "Sign In") {
                            if isSignUp {
                                authManager.signUpWithEmail(email: email, password: password, name: name) { success in
                                    if success {
                                        dismiss()
                                    } else {
                                        showingAlert = true
                                    }
                                }
                            } else {
                                authManager.signInWithEmail(email: email, password: password) { success in
                                    if success {
                                        dismiss()
                                    } else {
                                        showingAlert = true
                                    }
                                }
                            }
                        }
                        .disabled(email.isEmpty || password.isEmpty || (isSignUp && name.isEmpty))
                    }
                    
                    if authManager.isLoading {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(isSignUp ? "Create Account" : "Sign In")
                .alert(isPresented: $showingAlert) {
                    Alert(
                        title: Text("Error"),
                        message: Text(authManager.errorMessage ?? "An unknown error occurred"),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .disabled(authManager.isLoading)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // Profile view for managing user settings
    struct ProfileView: View {
        @ObservedObject var authManager: AuthManager
        @Environment(\.dismiss) var dismiss
        @State private var emailNotificationsEnabled = true
        @State private var emailFrequency = UserProfile.EmailFrequency.weekly
        @State private var showingLogoutAlert = false
        @State private var showingSuccessAlert = false
        
        var body: some View {
            NavigationView {
                Form {
                    if let user = authManager.currentUser {
                        Section(header: Text("Account")) {
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(user.email)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let displayName = user.displayName {
                                HStack {
                                    Text("Name")
                                    Spacer()
                                    Text(displayName)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Section(header: Text("Email Notifications")) {
                            Toggle("Enable Email Reports", isOn: $emailNotificationsEnabled)
                            
                            if emailNotificationsEnabled {
                                Picker("Frequency", selection: $emailFrequency) {
                                    ForEach(UserProfile.EmailFrequency.allCases, id: \.self) { frequency in
                                        Text(frequency.rawValue).tag(frequency)
                                    }
                                }
                            }
                        }
                        
                        Section {
                            Button("Save Preferences") {
                                authManager.updateEmailPreferences(
                                    enabled: emailNotificationsEnabled,
                                    frequency: emailFrequency
                                ) { success in
                                    if success {
                                        showingSuccessAlert = true
                                    }
                                }
                            }
                            .disabled(authManager.isLoading)
                        }
                        
                        Section {
                            Button("Sign Out") {
                                showingLogoutAlert = true
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle("Your Profile")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .alert(isPresented: $showingLogoutAlert) {
                    Alert(
                        title: Text("Sign Out"),
                        message: Text("Are you sure you want to sign out?"),
                        primaryButton: .destructive(Text("Sign Out")) {
                            authManager.signOut()
                            dismiss()
                        },
                        secondaryButton: .cancel()
                    )
                }
                .overlay(
                    Group {
                        if authManager.isLoading {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }
                )
                .onAppear {
                    if let user = authManager.currentUser {
                        emailNotificationsEnabled = user.emailNotificationsEnabled
                        emailFrequency = user.emailFrequency
                    }
                }
                .onChange(of: showingSuccessAlert) {
                    if showingSuccessAlert {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showingSuccessAlert = false
                        }
                    }
                }

                .overlay(
                    Group {
                        if showingSuccessAlert {
                            VStack {
                                Text("Preferences saved successfully!")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(10)
                                    .shadow(radius: 3)
                            }
                            .padding()
                            .transition(.move(edge: .top))
                            .animation(.easeInOut, value: showingSuccessAlert)
                        }
                    }
                )
            }
        }
    }

    // SwiftUI app entry point
    @main
    struct PomoPulseApp: App {
        @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
        
        var body: some Scene {
            WindowGroup {
                ContentView()
            }
        }
    }
