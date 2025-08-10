# Firebase Admin Setup Guide

This guide will help you set up Firebase for the EV Charging App admin functionality.

## Prerequisites

1. **Firebase Project**: You should have a Firebase project created at [Firebase Console](https://console.firebase.google.com/)
2. **Firebase CLI**: Install Firebase CLI globally
   ```bash
   npm install -g firebase-tools
   ```
3. **Node.js**: Make sure you have Node.js installed

## Step 1: Firebase CLI Setup

1. **Login to Firebase**:
   ```bash
   firebase login
   ```

2. **Initialize Firebase in your project**:
   ```bash
   firebase init
   ```
   - Select your project
   - Choose Firestore and Hosting (optional)
   - Use the default settings

## Step 2: Deploy Security Rules

1. **Deploy Firestore security rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```

   This will deploy the rules from `firestore.rules` to your Firebase project.

## Step 3: Create Admin User

### Option A: Using Firebase Console (Recommended)

1. **Create Authentication User**:
   - Go to Firebase Console > Authentication > Users
   - Click "Add User"
   - Enter admin email and password
   - Note down the UID

2. **Add to Admins Collection**:
   - Go to Firebase Console > Firestore Database
   - Create a collection called "admins"
   - Add a document with the UID as document ID
   - Add these fields:
     ```json
     {
       "email": "admin@example.com",
       "role": "admin",
       "created_at": "2024-01-01T00:00:00Z"
     }
     ```

### Option B: Using Admin SDK Script

1. **Get Service Account Key**:
   - Go to Firebase Console > Project Settings > Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file as `serviceAccountKey.json` in your project root

2. **Install Dependencies**:
   ```bash
   npm install
   ```

3. **Run Setup Script**:
   ```bash
   npm run setup
   ```

## Step 4: Test Admin Access

1. **Run your Flutter app**:
   ```bash
   flutter run
   ```

2. **Navigate to Admin Login**:
   - Use the admin credentials you created
   - Check console logs for any errors

3. **Verify Admin Dashboard**:
   - Should be able to see stations, users, and transactions
   - All CRUD operations should work

## Troubleshooting

### Common Issues

1. **"User is not an admin" Error**:
   - Make sure the user exists in the `admins` collection
   - Check that the document ID matches the user's UID

2. **"Permission denied" Error**:
   - Verify security rules are deployed correctly
   - Check that the user is authenticated

3. **"Collection not found" Error**:
   - Collections will be created automatically when first document is added
   - Or run the setup script to create sample data

4. **Authentication Errors**:
   - Verify Firebase Auth is enabled in your project
   - Check that email/password authentication is enabled

### Debug Steps

1. **Check Firebase Console**:
   - Verify collections exist in Firestore
   - Check Authentication users
   - Review security rules

2. **Check Flutter Console**:
   - Look for detailed error messages
   - Verify Firebase initialization

3. **Test with Firebase CLI**:
   ```bash
   firebase firestore:get /admins
   ```

## Security Considerations

1. **Admin Access**: Only users in the `admins` collection can access admin features
2. **Data Protection**: Users can only access their own data
3. **Authentication**: All operations require Firebase Auth
4. **Rules**: Security rules prevent unauthorized access

## Next Steps

After setting up admin access:

1. **Create Sample Data**: Use the setup script to populate collections
2. **Test All Features**: Verify CRUD operations work correctly
3. **Monitor Usage**: Check Firebase Console for usage metrics
4. **Scale**: Add more admin users as needed

## Support

If you encounter issues:

1. Check the Firebase Console for error logs
2. Review the security rules syntax
3. Verify all collections exist
4. Test with a simple Firebase query first 