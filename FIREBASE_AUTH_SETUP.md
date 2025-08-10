# Firebase Authentication Setup Guide

This guide will help you set up Firebase Authentication with Google Sign-In for your Flutter EV Charging App.

## Prerequisites

1. A Firebase project
2. Flutter SDK installed
3. Android Studio / VS Code with Flutter extensions

## Step 1: Firebase Project Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select an existing one
3. Enable Authentication:
   - Go to Authentication > Sign-in method
   - Enable "Email/Password" provider
   - Enable "Google" provider
   - Configure Google Sign-In with your OAuth 2.0 client ID

## Step 2: Android Configuration

### 2.1 Add Firebase to Android App

1. In Firebase Console, go to Project Settings
2. Add Android app with package name: `com.example.my_flutter_app`
3. Download `google-services.json` and place it in `android/app/`
4. Update `android/build.gradle`:

```gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.3.15'
    }
}
```

5. Update `android/app/build.gradle`:

```gradle
apply plugin: 'com.google.gms.google-services'

android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### 2.2 Configure Google Sign-In

1. Get your SHA-1 fingerprint:
```bash
cd android
./gradlew signingReport
```

2. Add the SHA-1 to your Firebase project:
   - Go to Project Settings > Your Apps > Android app
   - Add fingerprint

## Step 3: iOS Configuration (if needed)

1. Add iOS app in Firebase Console
2. Download `GoogleService-Info.plist`
3. Add to iOS project via Xcode
4. Update `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>REVERSED_CLIENT_ID</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

## Step 4: Web Configuration (if needed)

1. Add Web app in Firebase Console
2. Update `web/index.html`:

```html
<head>
    <!-- Add before closing head tag -->
    <script src="https://www.gstatic.com/firebasejs/9.0.0/firebase-app.js"></script>
    <script src="https://www.gstatic.com/firebasejs/9.0.0/firebase-auth.js"></script>
</head>
```

## Step 5: Flutter Configuration

The app is already configured with the necessary dependencies:

- `firebase_core: ^3.6.0`
- `firebase_auth: ^5.3.3`
- `google_sign_in: ^6.2.1`

## Step 6: Testing

1. Run the app:
```bash
flutter run
```

2. Test authentication features:
   - Email/Password sign up
   - Email/Password sign in
   - Google Sign-In
   - Password reset
   - Sign out

## Features Implemented

### Authentication Methods
- ✅ Email/Password Sign Up
- ✅ Email/Password Sign In
- ✅ Google Sign-In
- ✅ Password Reset
- ✅ Sign Out

### UI Features
- ✅ Modern login/signup screens
- ✅ Social login buttons
- ✅ Form validation
- ✅ Error handling
- ✅ Loading states
- ✅ Forgot password dialog

### Firebase Integration
- ✅ User data stored in Firestore
- ✅ Automatic wallet creation for new users
- ✅ Auth state management
- ✅ Real-time authentication state

## Troubleshooting

### Common Issues

1. **Google Sign-In not working**
   - Check SHA-1 fingerprint is added to Firebase
   - Verify OAuth 2.0 client ID is configured
   - Ensure Google Sign-In is enabled in Firebase Console

2. **Firebase initialization error**
   - Verify `google-services.json` is in correct location
   - Check Firebase project configuration
   - Ensure all dependencies are properly installed

3. **Build errors**
   - Run `flutter clean` and `flutter pub get`
   - Check Android SDK version compatibility
   - Verify all Firebase dependencies are compatible

### Debug Commands

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run

# Check Firebase configuration
flutter doctor
```

## Security Notes

1. Never commit sensitive Firebase configuration files to public repositories
2. Use Firebase Security Rules to protect your Firestore data
3. Implement proper error handling for authentication failures
4. Consider implementing email verification for new accounts

## Next Steps

1. Implement email verification
2. Add Facebook Sign-In
3. Implement user profile management
4. Add biometric authentication
5. Implement session management
6. Add admin authentication

## Support

For issues related to:
- Firebase: Check [Firebase Documentation](https://firebase.google.com/docs)
- Flutter: Check [Flutter Documentation](https://flutter.dev/docs)
- Google Sign-In: Check [Google Sign-In Documentation](https://developers.google.com/identity/sign-in/android) 