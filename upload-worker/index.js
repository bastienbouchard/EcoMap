const FIREBASE_API_KEY = 'AIzaSyACM479_zu4rESc_e1J_o6lBs--WzMMTPc';
const FIREBASE_PROJECT_ID = 'moosesense-a84cf';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (url.pathname === '/stripe-webhook') {
      return handleStripeWebhook(request, env);
    }

    return handleUpload(request, env);
  },
};

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Filename',
  };
}

// ── Upload photo ────────────────────────────────────────────────────────────

async function handleUpload(request, env) {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 });
  }
  const idToken = authHeader.slice(7);

  // Vérifie le token Firebase
  const verifyResp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    }
  );
  if (!verifyResp.ok) {
    return new Response('Unauthorized', { status: 401 });
  }

  const filename = request.headers.get('X-Filename') || `${Date.now()}.jpg`;
  const body = await request.arrayBuffer();

  await env.BUCKET.put(`chat/${filename}`, body, {
    httpMetadata: { contentType: 'image/jpeg' },
  });

  const publicUrl = `${env.PUBLIC_URL}/chat/${filename}`;
  return new Response(JSON.stringify({ url: publicUrl }), {
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

// ── Stripe webhook ──────────────────────────────────────────────────────────

async function handleStripeWebhook(request, env) {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const body = await request.text();
  const signature = request.headers.get('stripe-signature');

  if (!signature || !env.STRIPE_WEBHOOK_SECRET) {
    return new Response('Missing config', { status: 400 });
  }

  const isValid = await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET);
  if (!isValid) {
    return new Response('Invalid signature', { status: 400 });
  }

  const event = JSON.parse(body);

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const uid = session.client_reference_id;
    if (uid) {
      await setUserPremium(uid, env);
    }
  }

  return new Response('ok', { status: 200 });
}

async function verifyStripeSignature(payload, signature, secret) {
  const parts = {};
  for (const part of signature.split(',')) {
    const [key, ...rest] = part.split('=');
    parts[key] = rest.join('=');
  }

  const timestamp = parts.t;
  const expectedSig = parts.v1;
  if (!timestamp || !expectedSig) return false;

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - parseInt(timestamp)) > 300) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(`${timestamp}.${payload}`));
  const sigHex = Array.from(new Uint8Array(sig))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');

  return sigHex === expectedSig;
}

// ── Firestore via service account ───────────────────────────────────────────

async function setUserPremium(uid, env) {
  const accessToken = await getAccessToken(env);
  if (!accessToken) return;

  // updateMask pour ne modifier que le champ premium
  const firestoreUrl =
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${uid}` +
    `?updateMask.fieldPaths=premium`;

  await fetch(firestoreUrl, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fields: { premium: { booleanValue: true } },
    }),
  });
}

async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: env.FIREBASE_CLIENT_EMAIL,
    sub: env.FIREBASE_CLIENT_EMAIL,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/datastore',
  };

  const b64 = (obj) =>
    btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const signingInput = `${b64(header)}.${b64(payload)}`;

  const pem = env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n');
  const pemContent = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');

  const binary = atob(pemContent);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);

  const key = await crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const encoder = new TextEncoder();
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    encoder.encode(signingInput)
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  const jwt = `${signingInput}.${sigB64}`;

  const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenResp.ok) return null;
  const data = await tokenResp.json();
  return data.access_token;
}
