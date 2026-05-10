importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts(
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyD6gXLQsxiQ55ytoZmsgpwTfezWbMomn4Y',
  authDomain: 'budisciplink.web.app',
  projectId: 'myapp-e5237',
  storageBucket: 'myapp-e5237.firebasestorage.app',
  messagingSenderId: '486417428487',
  appId: '1:486417428487:web:4d97c48e7a5ceace293aa2',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload?.notification?.title || payload?.data?.title || 'BUDiscipLink';
  const body = payload?.notification?.body || payload?.data?.body || '';
  const clickLink = payload?.data?.link || '/';
  const notificationOptions = {
    body,
    icon: '/icons/Icon-192-bud.png',
    badge: '/icons/Icon-192-bud.png',
    data: {
      link: clickLink,
    },
  };
  self.registration.showNotification(title, notificationOptions);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = event.notification?.data?.link || '/';
  event.waitUntil(clients.openWindow(target));
});
