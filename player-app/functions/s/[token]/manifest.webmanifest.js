const TOKEN_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WORKER_BASE = "https://api.uk.sportsmanager.site";

export async function onRequestGet({ params }) {
  const token = String(params.token ?? "").toLowerCase();
  if (!TOKEN_RE.test(token)) {
    return new Response("Not found", { status: 404 });
  }

  let managerName = null;
  try {
    const res = await fetch(`${WORKER_BASE}/s/${token}`);
    if (res.ok) {
      const data = await res.json();
      managerName = data.managerName ?? null;
    }
  } catch {
    // Fall back to generic name if Worker is unreachable.
  }

  const shortName = managerName ? `LSM ${managerName}` : "LSM Submit";
  const fullName = managerName
    ? `Last Stand Manager — ${managerName}`
    : "Last Stand Manager — Submit";

  return Response.json({
    name: fullName,
    short_name: shortName,
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
