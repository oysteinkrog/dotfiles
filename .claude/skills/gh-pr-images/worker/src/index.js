// gh-pr-images Worker: front a private R2 bucket so screenshots can be embedded
// inline in GitHub PR/issue comments (including private repos) without committing
// them to git and without putting any secret in the repo.
//
//   PUT  /?prefix=<p>&name=<file>   upload an image, returns { url, key }
//   GET  /<key>                     serve a previously uploaded image
//
// The R2 bucket is bound as BUCKET on Cloudflare and is never public on its own;
// this Worker is the only public surface. The client needs only the Worker URL,
// which is not a secret: a leak grants at most the ability to upload an image
// (PUT is image-only, size-capped, and writes server-generated random keys, so it
// cannot overwrite or enumerate existing objects). Set the optional UPLOAD_TOKEN
// secret to additionally gate uploads behind a bearer token.

const MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

function randomKey(prefix, name) {
  const id = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
  const safe = (name || "image").replace(/[^A-Za-z0-9._-]/g, "_").slice(-80);
  const p = (prefix || "uploads")
    .replace(/[^A-Za-z0-9._/-]/g, "_")
    .replace(/^\/+|\/+$/g, "");
  return `${p || "uploads"}/${id}-${safe}`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "PUT" || request.method === "POST") {
      if (env.UPLOAD_TOKEN) {
        const auth = request.headers.get("authorization") || "";
        if (auth !== `Bearer ${env.UPLOAD_TOKEN}`) {
          return new Response("unauthorized\n", { status: 401 });
        }
      }

      const contentType = (request.headers.get("content-type") || "")
        .split(";")[0]
        .trim()
        .toLowerCase();
      if (!ALLOWED[contentType]) {
        return new Response(`unsupported content-type: ${contentType}\n`, {
          status: 415,
        });
      }

      const declaredLen = Number(request.headers.get("content-length") || "0");
      if (declaredLen > MAX_BYTES) {
        return new Response("file too large\n", { status: 413 });
      }

      const body = await request.arrayBuffer();
      if (body.byteLength > MAX_BYTES) {
        return new Response("file too large\n", { status: 413 });
      }

      const name =
        request.headers.get("x-filename") ||
        url.searchParams.get("name") ||
        `image.${ALLOWED[contentType]}`;
      const key = randomKey(url.searchParams.get("prefix"), name);

      await env.BUCKET.put(key, body, {
        httpMetadata: { contentType, contentDisposition: "inline" },
      });

      return Response.json({ url: `${url.origin}/${key}`, key });
    }

    if (request.method === "GET" || request.method === "HEAD") {
      const key = decodeURIComponent(url.pathname.replace(/^\/+/, ""));
      if (!key) {
        return new Response(
          "gh-pr-images: PUT an image to upload; GET /<key> to fetch.\n",
          { status: 200 },
        );
      }
      const object = await env.BUCKET.get(key);
      if (!object) {
        return new Response("not found\n", { status: 404 });
      }
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      headers.set("cache-control", "public, max-age=31536000, immutable");
      return new Response(request.method === "HEAD" ? null : object.body, {
        headers,
      });
    }

    return new Response("method not allowed\n", {
      status: 405,
      headers: { allow: "GET, PUT" },
    });
  },
};
