const TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function onRequestGet({ params }) {
  const token = String(params.token ?? "").toLowerCase();
  if (!TOKEN_RE.test(token)) {
    return new Response("Not found", { status: 404 });
  }

  return Response.json({
    name: "Last Stand Manager - Submit",
    short_name: "LSM Submit",
    description: "Submit your pick or score prediction. Reviewed by your game's manager before it goes live.",
    start_url: `/s/${token}`,
    scope: "/",
    display: "standalone",
    background_color: "#0B1220",
    theme_color: "#0B1220",
    icons: [
      {
        src: "/logo.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/logo.png",
        sizes: "512x512",
        type: "image/png",
      },
      {
        src: "/logo.png",
        sizes: "1024x1024",
        type: "image/png",
        purpose: "any maskable",
      },
    ],
  }, {
    headers: {
      "Content-Type": "application/manifest+json; charset=utf-8",
      "Cache-Control": "private, max-age=300",
    },
  });
}
