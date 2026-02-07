export default async function handler(req, res) {
  const token = (process.env.GITHUB_TOKEN || "").trim();
  if (!token) {
    return res.status(500).json({
      ok: false,
      error: "GITHUB_TOKEN_MISSING",
      message: "Server is not configured with a GitHub token. Set GITHUB_TOKEN in Vercel env vars.",
    });
  }

  const { owner, repo } = req.query;
  const state = (req.query.state || "open").trim();
  const page = Math.max(1, Number(req.query.page || "1"));
  const per_page = Math.min(100, Math.max(1, Number(req.query.per_page || "30")));

  if (!owner || !repo) {
    return res.status(400).json({
      ok: false,
      error: "BAD_REQUEST",
      message: "Missing required query params: owner, repo",
    });
  }

  const ghUrl = new URL(`https://api.github.com/repos/${owner}/${repo}/issues`);
  ghUrl.searchParams.set("state", state);
  ghUrl.searchParams.set("page", String(page));
  ghUrl.searchParams.set("per_page", String(per_page));

  const ghRes = await fetch(ghUrl.toString(), {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "gitbounty-vercel-api",
    },
  });

  if (!ghRes.ok) {
    const text = await ghRes.text().catch(() => "");
    const status = ghRes.status;
    return res.status(status).json({
      ok: false,
      error:
        status === 401
          ? "GITHUB_TOKEN_INVALID"
          : status === 403
          ? "GITHUB_FORBIDDEN_OR_RATE_LIMIT"
          : "GITHUB_REQUEST_FAILED",
      message: `GitHub API responded with ${status} ${ghRes.statusText}`,
      githubStatus: status,
      rateLimit: {
        limit: ghRes.headers.get("x-ratelimit-limit"),
        remaining: ghRes.headers.get("x-ratelimit-remaining"),
        reset: ghRes.headers.get("x-ratelimit-reset"),
      },
      bodySnippet: text.slice(0, 400),
    });
  }

  const issues = await ghRes.json();
  return res.status(200).json({ ok: true, issues });
}
