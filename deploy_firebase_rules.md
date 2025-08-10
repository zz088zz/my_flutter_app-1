# Firebase Security Rules Deployment Guide

## Prerequisites
1. Install Firebase CLI: `npm install -g firebase-tools`
2. Login to Firebase: `firebase login`
3. Initialize Firebase in your project: `firebase init`

## Deploy Security Rules

1. **Deploy Firestore Rules:**
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Deploy All Firebase Services:**
   ```bash
   firebase deploy
   ```

## Create Admin User

To create an admin user in Firebase:

1. **Create a user account in Firebase Auth:**
   - Go to Firebase Console > Authentication > Users
   - Click "Add User"
   - Enter email and password

2. **Add user to admins collection:**
   - Go to Firebase Console > Firestore Database
   - Create a collection called "admins"
   - Add a document with the user's UID as the document ID
   - Add fields like:
     ```json
     {
       "email": "admin@example.com",
       "role": "admin",
       "created_at": "2024-01-01T00:00:00Z"
     }
     ```

## Test Admin Access

1. Use the admin credentials in your Flutter app
2. Check the console logs for any permission errors
3. Verify that admin can access all collections

## Troubleshooting

- **Permission Denied Errors:** Check if the user exists in the admins collection
- **Collection Not Found:** Ensure collections exist in Firestore
- **Authentication Errors:** Verify Firebase Auth is properly configured 