import * as admin from 'firebase-admin';
import { env } from './env.js';

let firebaseApp: admin.app.App | null = null;
let firebaseEnabled = false;

export function getFirebaseApp(): admin.app.App | null {
  return firebaseApp;
}

export function isFirebaseEnabled(): boolean {
  return firebaseEnabled;
}

export function getMessaging(): admin.messaging.Messaging | null {
  if (!firebaseApp) return null;
  return firebaseApp.messaging();
}

// 앱 초기화 (서버 시작 시 호출 — Firebase 없어도 서버는 정상 기동)
export function initFirebase(): void {
  if (!env.FIREBASE_SERVICE_ACCOUNT || env.FIREBASE_SERVICE_ACCOUNT.trim() === '') {
    console.warn('[Firebase] FIREBASE_SERVICE_ACCOUNT not set — push notifications disabled');
    return;
  }

  try {
    const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT) as admin.ServiceAccount;

    firebaseApp = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });

    firebaseEnabled = true;
    console.info('[Firebase] Admin SDK initialized');
  } catch (err) {
    console.warn('[Firebase] Failed to initialize — push notifications disabled:', (err as Error).message);
  }
}
