# Phone Authentication Troubleshooting Guide

## Quick Checklist

### ✅ Step 1: Verify Firebase Console Setup

1. **Go to [Firebase Console](https://console.firebase.google.com/)**
2. **Select your project: "hoidma"**
3. **Check Authentication:**
   - Go to **Authentication** > **Sign-in method**
   - Find **Phone** in the list
   - Ensure it's **Enabled** (toggle should be ON)
   - If not enabled, click on it and toggle it ON, then click "Save"

### ✅ Step 2: Verify iOS App Registration

1. **In Firebase Console:**
   - Click the **gear icon** (⚙️) next to "Project Overview"
   - Select **Project settings**
   - Scroll to **Your apps** section
   - Verify you have an iOS app with:
     - **Bundle ID:** `danielfurry.Hoidma`
     - **App ID:** `1:702099938315:ios:e06843301dad712267bb0e`

2. **If the app is missing:**
   - Click **Add app** > iOS icon
   - Enter bundle ID: `danielfurry.Hoidma`
   - Download the new `GoogleService-Info.plist`
   - Replace the existing file in your Xcode project

### ✅ Step 3: Verify GoogleService-Info.plist in Xcode

1. **In Xcode:**
   - Find `GoogleService-Info.plist` in the project navigator
   - Click on it
   - Open the **File Inspector** (right panel, or press `Cmd+Option+1`)
   - Under **Target Membership**, ensure **Hoidma** is checked ✅
   - If not checked, check it

2. **Verify the file is in the correct location:**
   - Path should be: `Hoidma/Hoidma/GoogleService-Info.plist`
   - It should be inside the `Hoidma` folder (same level as your Swift files)

### ✅ Step 4: Clean and Rebuild

1. **In Xcode:**
   - **Product** > **Clean Build Folder** (`Shift+Cmd+K`)
   - Wait for it to complete
   - **Product** > **Build** (`Cmd+B`)
   - Check for any errors

### ✅ Step 5: Test Phone Authentication

1. **Run the app on your iPhone**
2. **Enter your phone number** (with country code, e.g., +1 for US)
3. **Click "Send Code"**
4. **Check the Xcode console** for these messages:
   - `✅ Firebase configured successfully`
   - `✅ AuthManager: Firebase Auth initialized`
   - `✅ AuthManager: PhoneAuthProvider obtained`
   - `📱 AuthManager: Sending verification code to +...`

## Common Errors and Solutions

### Error: "Firebase not initialized"
**Solution:** 
- Make sure `GoogleService-Info.plist` is added to the target
- Clean build folder and rebuild
- Restart Xcode

### Error: "Invalid phone number"
**Solution:**
- Phone number must include country code
- Format: `+[country code][number]`
- Example: `+15742166565` (US number)

### Error: "SMS quota exceeded"
**Solution:**
- Firebase free tier has SMS limits
- Wait a few minutes and try again
- For testing, use Firebase test phone numbers (see below)

### Error: "Network error"
**Solution:**
- Check your internet connection
- Ensure your iPhone has cellular data or WiFi
- Try again

## Using Test Phone Numbers (Development)

For testing without using real SMS:

1. **In Firebase Console:**
   - Go to **Authentication** > **Sign-in method** > **Phone**
   - Scroll to **Phone numbers for testing**
   - Click **Add phone number**
   - Enter a test number (e.g., `+1 650-555-1234`)
   - Enter a test code (e.g., `123456`)
   - Click **Save**

2. **In your app:**
   - Use the test phone number you added
   - When prompted for verification code, enter the test code you set

## Verify Everything is Working

After following the steps above, you should see in the console:
```
✅ Firebase configured successfully
✅ Firebase app initialized: [DEFAULT]
✅ Bundle ID: danielfurry.Hoidma
✅ AuthManager: Firebase Auth initialized
📱 AuthManager: Sending verification code to +15742166565...
✅ AuthManager: PhoneAuthProvider obtained
✅ AuthManager: Verification code sent successfully, ID received
```

If you see all these messages, phone authentication is working! You should receive an SMS with a verification code.

## Still Having Issues?

1. **Check Xcode console** for specific error messages
2. **Verify Phone Auth is enabled** in Firebase Console
3. **Ensure bundle ID matches** exactly: `danielfurry.Hoidma`
4. **Try deleting and reinstalling the app** on your iPhone
5. **Restart Xcode** and rebuild
