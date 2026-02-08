# Hoop Metric 🏀

A basketball training app built with Expo and React Native that uses computer vision to track and count basketball dribbles in real-time.

## Features

- **Dribble Detection**: Real-time basketball dribble counting using machine learning and computer vision
- **Visual Feedback**: Live ball tracking with visual indicators
- **Timer-Based Drills**: 60-second timed dribble drills with countdown timer
- **Camera Integration**: Uses device camera with `react-native-vision-camera` for frame processing
- **Landscape Mode**: Optimized for landscape orientation during drills

## Tech Stack

- **Framework**: Expo (~54.0.33)
- **React Native**: 0.81.5
- **Camera**: react-native-vision-camera (^4.7.1)
- **ML Processing**: react-native-worklets-core (^1.6.2)
- **Navigation**: Expo Router (file-based routing)
- **Language**: TypeScript

## Prerequisites

- Node.js (v18 or later recommended)
- npm or yarn
- iOS Simulator (for iOS development) or Android Studio (for Android development)
- For physical device testing: Expo Go app or development build

## Getting Started

1. **Install dependencies**

   ```bash
   npm install
   ```

2. **Start the development server**

   ```bash
   npx expo start
   ```

3. **Run on your preferred platform**

   - Press `i` for iOS simulator
   - Press `a` for Android emulator
   - Scan QR code with Expo Go app for physical device

## Project Structure

```
├── app/                    # Expo Router pages
│   ├── (tabs)/            # Tab navigation screens
│   └── _layout.tsx        # Root layout
├── features/              # Feature modules
│   └── DribbleDrill/      # Dribble detection feature
├── components/            # Reusable components
├── ios/                   # iOS native code
│   └── BallDetector/      # Native ball detection module
└── android/               # Android native code
```

## Development

### Available Scripts

- `npm start` - Start Expo development server
- `npm run android` - Run on Android
- `npm run ios` - Run on iOS
- `npm run web` - Run on web
- `npm run lint` - Run ESLint

### Camera Permissions

The app requires camera permissions to function. These are configured in:
- iOS: `app.json` (NSCameraUsageDescription)
- Android: `AndroidManifest.xml`

## How It Works

The DribbleDrill feature uses:
1. **Frame Processing**: Captures camera frames at 25 FPS
2. **Ball Detection**: Uses a machine learning model to detect basketball position
3. **Motion Tracking**: Tracks vertical movement patterns to identify dribbles
4. **Bounce Detection**: Analyzes amplitude and direction changes to count valid dribbles
5. **Visual Feedback**: Displays ball position

## License

Private project
