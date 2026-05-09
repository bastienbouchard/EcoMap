export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-Auth-Token, X-Filename',
        },
      });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    // Vérification token simple
    const token = request.headers.get('X-Auth-Token');
    if (token !== env.UPLOAD_SECRET) {
      return new Response('Unauthorized', { status: 401 });
    }

    const filename = request.headers.get('X-Filename') || `${Date.now()}.jpg`;
    const body = await request.arrayBuffer();

    await env.BUCKET.put(`chat/${filename}`, body, {
      httpMetadata: { contentType: 'image/jpeg' },
    });

    const url = `${env.PUBLIC_URL}/chat/${filename}`;

    return new Response(JSON.stringify({ url }), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  },
};
