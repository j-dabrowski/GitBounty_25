export default async function handler(req, res) {
  const { owner, repo } = req.query;
  const state = req.query.state || "open";
  const page = Math.max(1, Number(req.query.page || "1"));
  const per_page = Math.min(100, Math.max(1, Number(req.query.per_page || "30")));

  if (!owner || !repo) return res.status(400).json({ error: "Missing owner/repo" });

  const ghUrl = new URL(`https://api.github.com/repos/${owner}/${repo}/issues`);
  ghUrl.searchParams.set("state", state);
  ghUrl.searchParams.set("page", String(page));
  ghUrl.searchParams.set("per_page", String(per_page));

  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "gitbounty-issue-browser",
  };

  // Optional: add later in Vercel env vars
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const ghRes = await fetch(ghUrl.toString(), { headers });

  if (!ghRes.ok) {
    const text = await ghRes.text();
    return res.status(ghRes.status).json({ error: "GitHub request failed", details: text });
  }

  const items = await ghRes.json();
  const issuesOnly = items
    .filter((x) => !x.pull_request)
    .map((x) => ({
      number: x.number,
      title: x.title,
      state: x.state,
      html_url: x.html_url,
      created_at: x.created_at,
      updated_at: x.updated_at,
      labels: (x.labels || []).map((l) => (typeof l === "string" ? l : l.name)),
      author: x.user?.login || null,
      comments: x.comments ?? 0,
    }));

  // Light caching hint (Vercel may respect / propagate; still helpful)
  res.setHeader("Cache-Control", "public, s-maxage=60, stale-while-revalidate=300");
  return res.status(200).json({ owner, repo, state, page, per_page, items: issuesOnly });
}
