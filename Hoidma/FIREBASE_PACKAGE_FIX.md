# Fixing FirebaseCore Package Error

## Quick Fix Steps (Do These in Order)

### Step 1: Close Xcode Completely
- Press `Cmd+Q` to quit Xcode (don't just close the window)

### Step 2: Clear Xcode Caches
Run these commands in Terminal:
```bash
cd ~/Library/Developer/Xcode/DerivedData
rm -rf Hoidma-*
```

### Step 3: Reopen Xcode and Project
- Open Xcode
- Open your Hoidma project

### Step 4: Reset Package Caches
1. In Xcode menu: **File > Packages > Reset Package Caches**
2. Wait for it to complete (watch the progress indicator)

### Step 5: Resolve Package Versions
1. In Xcode menu: **File > Packages > Resolve Package Versions**
2. Wait for all packages to download (this may take 2-3 minutes)
3. You should see progress in the top status bar

### Step 6: Verify Packages in Project Settings
1. Click the **blue project icon** at the top of the navigator (left sidebar)
2. Select the **Hoidma project** (not the target, the project itself)
3. Click the **Package Dependencies** tab
4. You should see:
   - `firebase-ios-sdk` (version 10.19.0 or higher)
   - `SwiftYFinance` (version 1.4.0 or higher)
5. If either is missing, click the **+** button and add them

### Step 7: Verify Target Dependencies
1. Still in project settings, select the **Hoidma target** (under TARGETS)
2. Go to the **General** tab
3. Scroll down to **Frameworks, Libraries, and Embedded Content**
4. You should see all 5 packages listed:
   - FirebaseCore
   - FirebaseAuth
   - FirebaseFirestore
   - FirebaseFirestoreSwift
   - SwiftYFinance
5. If any are missing:
   - Click the **+** button
   - Search for the missing package
   - Add it (make sure it's from the correct source)

### Step 8: Clean Build Folder
1. **Product > Clean Build Folder** (or press `Shift+Cmd+K`)
2. Wait for it to complete

### Step 9: Build the Project
1. Select a **simulator** as the destination (e.g., iPhone 15)
2. Press `Cmd+B` to build
3. Wait for the build to complete

### Step 10: If Still Failing - Manual Package Re-add
If packages still don't work:

1. **Remove packages:**
   - Project settings > Package Dependencies tab
   - Select each package and click **-** to remove
   - Confirm removal

2. **Re-add packages:**
   - Click **+** button
   - Search for: `https://github.com/firebase/firebase-ios-sdk`
   - Add it with version "Up to Next Major Version" starting at 10.19.0
   - Click **+** again
   - Search for: `https://github.com/AlexRoar/SwiftYFinance`
   - Add it with version "Up to Next Major Version" starting at 1.4.0

3. **Add products to target:**
   - Select Hoidma target > General tab
   - Frameworks, Libraries, and Embedded Content
   - Click **+** and add each Firebase product and SwiftYFinance

4. **Build again**

## Firebase Website Setup Verification

### ✅ Check 1: Project Exists
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Verify your project "hoidma" exists
3. If not, create it following the FIREBASE_SETUP.md guide

### ✅ Check 2: iOS App is Registered
1. In Firebase Console, click the **gear icon** (⚙️) next to "Project Overview"
2. Select **Project settings**
3. Scroll to **Your apps** section
4. Verify you have an iOS app with bundle ID: `danielfurry.Hoidma`
5. If missing, click **Add app** > iOS icon and register it

### ✅ Check 3: GoogleService-Info.plist is Correct
1. In Firebase Console > Project settings > Your apps
2. Click on your iOS app
3. Download the `GoogleService-Info.plist` file
4. Compare it with your current file at: `/Users/daniel.furry/hoidma/Hoidma/Hoidma/GoogleService-Info.plist`
5. Make sure the BUNDLE_ID matches: `danielfurry.Hoidma`

### ✅ Check 4: Phone Authentication is Enabled
1. In Firebase Console, go to **Authentication** > **Sign-in method**
2. Click on **Phone** provider
3. Verify it's **Enabled** (toggle should be ON)
4. If not enabled, toggle it ON and click **Save**

### ✅ Check 5: Firestore Database is Enabled
1. In Firebase Console, go to **Firestore Database**
2. If you see "Get started", click it
3. Choose **Start in test mode** (for development)
4. Select a location (choose closest to you)
5. Click **Enable**

### ✅ Check 6: Firestore Security Rules (Important!)
1. In Firebase Console > Firestore Database > **Rules** tab
2. Update rules to allow authenticated users to read/write their own data:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow users to read/write their own portfolio data
    match /portfolios/{userId}/stocks/{stockId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

3. Click **Publish**

## Common Issues and Solutions

### Issue: "Missing package product 'FirebaseCore'"
**Solution:** Follow Steps 1-9 above. The issue is usually Xcode's package cache.

### Issue: "No such module 'FirebaseCore'"
**Solution:** 
- Make sure you've imported it: `import FirebaseCore`
- Verify the package is in Frameworks, Libraries, and Embedded Content
- Clean build folder and rebuild

### Issue: "FirebaseApp.configure() failed"
**Solution:**
- Verify GoogleService-Info.plist is in your project
- Check that it's added to the target (right-click file > Get Info > Target Membership)
- Verify the bundle ID in the plist matches your app's bundle ID

### Issue: Packages download but don't link
**Solution:**
- Remove packages from Package Dependencies
- Close Xcode
- Delete DerivedData (Step 2 above)
- Reopen Xcode and re-add packages
- Make sure to add products to the target's Frameworks section

## Still Having Issues?

If you've completed all steps and still have issues:

1. **Check Xcode version:** Make sure you're using Xcode 15.0 or later
2. **Check internet connection:** Package downloads require internet
3. **Check Apple Developer account:** Make sure you're signed in (Xcode > Settings > Accounts)
4. **Try a different simulator:** Sometimes switching simulators helps
5. **Restart your Mac:** Sometimes Xcode's build system needs a fresh start
