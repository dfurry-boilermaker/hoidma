# Firebase Setup Instructions for Hoidma

This guide will help you set up Firebase for phone number authentication and Firestore database storage.

## Prerequisites

- A Firebase account (free tier is sufficient)
- Xcode installed
- CocoaPods or Swift Package Manager (SPM) - we'll use SPM

## Step 1: Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" or select an existing project
3. Follow the setup wizard:
   - Enter project name (e.g., "Hoidma")
   - Enable/disable Google Analytics (optional)
   - Click "Create project"

## Step 2: Add iOS App to Firebase

1. In Firebase Console, click the iOS icon to add an iOS app
2. Enter your iOS bundle ID:
   - **Your current bundle ID is**: `danielfurry.Hoidma`
   - To find/change it in Xcode: Select your project in the navigator → Select "Hoidma" target → General tab → Look for "Bundle Identifier"
   - To change it: Click on the bundle identifier and edit it (format: `com.yourcompany.appname`)
3. Enter App nickname (optional): "Hoidma iOS"
4. Enter App Store ID (optional, can skip for now)
5. Click "Register app"

## Step 3: Download GoogleService-Info.plist

1. Download the `GoogleService-Info.plist` file
2. **Important**: Add this file to your Xcode project:
   - Drag the file into the `Hoidma` folder in Xcode
   - Make sure "Copy items if needed" is checked
   - Select your app target
   - Click "Finish"

## Step 4: Enable Phone Authentication

1. In Firebase Console, go to **Authentication** > **Sign-in method**
2. Click on **Phone** provider
3. Enable it by toggling the switch
4. Click "Save"

**Note**: For production, you'll need to verify your app with Firebase. For development/testing, Firebase provides a test phone number format.

## Step 5: Enable Firestore Database

1. In Firebase Console, go to **Firestore Database**
2. Click "Create database"
3. Choose "Start in test mode" (for development)
   - **Important**: For production, you'll need to set up proper security rules
4. Select a location (choose closest to your users)
5. Click "Enable"

## Step 6: Set Up Security Rules (Important!)

1. In Firestore Database, go to the **Rules** tab
2. Replace the default rules with these (users can only access their own data):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own portfolio data
    match /portfolios/{userId}/stocks/{ticker} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

3. Click "Publish"

## Step 7: Add Firebase SDK to Xcode Project

### Using Swift Package Manager (Recommended)

1. In Xcode, go to **File** > **Add Packages...**
2. Enter this URL: `https://github.com/firebase/firebase-ios-sdk`
3. Click "Add Package"
4. Select these products:
   - ✅ **FirebaseAuth**
   - ✅ **FirebaseFirestore**
   - ✅ **FirebaseCore**
5. Click "Add Package"
6. Wait for the packages to download and integrate

## Step 8: Configure Firebase in Your App

The app is already configured to initialize Firebase in `HoidmaApp.swift`. Make sure your `GoogleService-Info.plist` is properly added to the project.

## Step 9: Test Phone Authentication

1. Build and run your app
2. Enter a phone number (for testing, Firebase provides test numbers)
3. You should receive a verification code via SMS
4. Enter the code to sign in

### Test Phone Numbers (Development)

Firebase provides test phone numbers for development. In Firebase Console:
- Go to **Authentication** > **Sign-in method** > **Phone**
- Scroll to "Phone numbers for testing"
- Add test numbers with verification codes

Example:
- Phone: `+1 650-555-1234`
- Code: `123456`

## Step 10: Verify Everything Works

1. Sign in with a phone number
2. Add a stock to your portfolio
3. Check Firebase Console > Firestore Database to see your data:
   - Should see: `portfolios/{userId}/stocks/{ticker}`

## Cost Considerations

### Free Tier (Spark Plan) - Perfect for 100s of users:
- **Firestore**: 
  - 1 GB storage
  - 50,000 reads/day
  - 20,000 writes/day
  - 20,000 deletes/day
- **Authentication**:
  - Unlimited users
  - Phone auth: Free for first 10K verifications/month, then $0.06/verification

### For 100s of users:
- Each user might read their portfolio ~10-20 times/day = ~2,000 reads/day total
- Each user might add/modify stocks ~1-2 times/day = ~200 writes/day total
- **You'll be well within the free tier!**

## Troubleshooting

### "Missing GoogleService-Info.plist"
- Make sure the file is in your Xcode project
- Check that it's added to your app target

### "Phone authentication not enabled"
- Verify Phone authentication is enabled in Firebase Console
- Check that you've enabled it in Authentication > Sign-in method

### "Permission denied" in Firestore
- Check your Firestore security rules
- Make sure the user is authenticated
- Verify the rules match the structure: `portfolios/{userId}/stocks/{ticker}`

### SMS not received
- Check that Phone auth is enabled
- For testing, use Firebase test phone numbers
- For production, verify your app in Firebase Console

## Next Steps

1. Set up proper Firestore security rules for production
2. Consider adding error handling and retry logic
3. Add analytics if desired
4. Set up app verification for production phone auth

## Support

- [Firebase Documentation](https://firebase.google.com/docs)
- [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
