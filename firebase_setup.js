const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json'); // You need to download this from Firebase Console

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'evcharging-aef0c'
});

const db = admin.firestore();

async function setupFirebaseCollections() {
  try {
    console.log('Setting up Firebase collections...');

    // Create sample charging stations
    const stations = [
      {
        name: 'Central Mall EV Station',
        address: '123 Main Street, City Center',
        latitude: 3.1390,
        longitude: 101.6869,
        total_spots: 4,
        available_spots: 3,
        power_output: 'Up to 50 kW',
        price_per_kwh: 0.35,
        is_available: true,
        created_at: admin.firestore.FieldValue.serverTimestamp()
      },
      {
        name: 'Shopping Complex Charging Hub',
        address: '456 Shopping Avenue, Downtown',
        latitude: 3.1420,
        longitude: 101.6880,
        total_spots: 6,
        available_spots: 4,
        power_output: 'Up to 75 kW',
        price_per_kwh: 0.40,
        is_available: true,
        created_at: admin.firestore.FieldValue.serverTimestamp()
      }
    ];

    for (const station of stations) {
      const stationRef = await db.collection('charging_stations').add(station);
      console.log(`Created station: ${station.name} with ID: ${stationRef.id}`);

      // Create chargers for this station
      const chargers = [
        {
          station_id: stationRef.id,
          name: 'Charger 1',
          type: 'Type 2',
          power: 22.0,
          price_per_kwh: station.price_per_kwh,
          is_available: true,
          created_at: admin.firestore.FieldValue.serverTimestamp()
        },
        {
          station_id: stationRef.id,
          name: 'Charger 2',
          type: 'CCS',
          power: 50.0,
          price_per_kwh: station.price_per_kwh,
          is_available: true,
          created_at: admin.firestore.FieldValue.serverTimestamp()
        }
      ];

      for (const charger of chargers) {
        await db.collection('chargers').add(charger);
      }
      console.log(`Created ${chargers.length} chargers for station: ${station.name}`);
    }

    // Create sample users
    const users = [
      {
        first_name: 'John',
        last_name: 'Doe',
        email: 'john.doe@example.com',
        phone_number: '+60123456789',
        created_at: admin.firestore.FieldValue.serverTimestamp()
      },
      {
        first_name: 'Jane',
        last_name: 'Smith',
        email: 'jane.smith@example.com',
        phone_number: '+60123456790',
        created_at: admin.firestore.FieldValue.serverTimestamp()
      }
    ];

    for (const user of users) {
      await db.collection('users').add(user);
      console.log(`Created user: ${user.first_name} ${user.last_name}`);
    }

    // Create sample transactions
    const transactions = [
      {
        user_id: 'sample_user_id_1',
        amount: 15.50,
        transaction_type: 'debit',
        description: 'Charging session at Central Mall EV Station',
        status: 'completed',
        created_at: admin.firestore.FieldValue.serverTimestamp()
      },
      {
        user_id: 'sample_user_id_2',
        amount: 25.00,
        transaction_type: 'credit',
        description: 'Wallet deposit',
        status: 'completed',
        created_at: admin.firestore.FieldValue.serverTimestamp()
      }
    ];

    for (const transaction of transactions) {
      await db.collection('transactions').add(transaction);
      console.log(`Created transaction: ${transaction.description}`);
    }

    console.log('Firebase collections setup completed successfully!');
  } catch (error) {
    console.error('Error setting up Firebase collections:', error);
  } finally {
    process.exit(0);
  }
}

// Run the setup
setupFirebaseCollections(); 