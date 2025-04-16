# Pomo-Pulse: Pomodoro Timer App

## Overview

Pomo-Pulse is a modern, feature-rich Pomodoro timer application built with SwiftUI. It helps users improve productivity through structured work and break intervals following the Pomodoro Technique.

## Features

- **Dynamic Timer Modes**:
  - Work sessions (default: 25 minutes)
  - Short breaks (default: 5 minutes)
  - Long breaks (default: 15 minutes)

- **Visual Progress Tracking**:
  - Circular progress indicator
  - Pomodoro counters to track completed work sessions
  - Dynamic backgrounds that change based on timer mode

- **Customizable Settings**:
  - Adjust work/break durations
  - Configure number of Pomodoros until a long break

- **Session History**:
  - Track all completed Pomodoro sessions
  - Filter history by session type
  - View productivity statistics

- **Cloud Sync**:
  - Sync session data across devices with Firebase
  - Secure user authentication

- **Email Reports**:
  - Customizable productivity summaries
  - Daily, weekly, or monthly frequency options
  - Beautifully formatted HTML emails

- **Notification Sounds**:
  - Audio alerts when sessions complete


## Requirements

- iOS 15.0 or later
- Xcode 13.0 or later
- Firebase account for cloud features

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/pomo-pulse.git
   cd pomo-pulse
   ```

2. Open the project in Xcode:
   ```bash
   open PomoPulse.xcodeproj
   ```

3. Install dependencies via Swift Package Manager (if not already configured):
   - Firebase/Auth
   - Firebase/Firestore
   - Firebase/Core

4. Set up Firebase:
   - Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
   - Add an iOS app to your Firebase project
   - Download the `GoogleService-Info.plist` file and add it to your Xcode project
   - Enable Authentication (Email/Password) and Firestore in your Firebase project

5. Build and run the app in Xcode

## Usage

### Basic Timer Controls

- **Start/Pause**: Begin or pause the current timer
- **Reset**: Reset the current timer to its initial value
- **Skip**: Skip to the next phase (work → break or break → work)

### Settings Configuration

1. Tap the gear icon to access settings
2. Adjust work duration, short break duration, and long break duration
3. Configure the number of Pomodoros until a long break

### User Account Features

1. Create an account to enable cloud sync
2. Configure email notification preferences in your profile
3. View your session history across all your devices

## Architecture

Pomo-Pulse follows a clean architecture approach with:

- SwiftUI for the user interface
- Firebase for authentication and data storage
- AVFoundation for sound playback
- MVVM (Model-View-ViewModel) pattern for separation of concerns

## Adding Custom Sounds

To add custom notification sounds:

1. Add your sound files to the Assets catalog as Data Sets
2. Modify the `soundPlayer` initialization in `ContentView` to use your custom sound

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
