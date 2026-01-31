export default async function handler(req, res) {
  const token = (process.env.GITHUB_TOKEN || "").trim();

  // 1) Fail hard if missing
  if (!token) {
    return res.status(500).json({
      ok: false,
      error: "GITHUB_TOKEN_MISSING",
      message:
        "Server is not configured with a GitHub token. Set GITHUB_TOKEN in Vercel env vars.",
    });
  }

  // (Optional) Validate query params
  const { owner, repo } = req.query;
  if (!owner || !repo) {
    return res.status(400).json({
      ok: false,
      error: "BAD_REQUEST",
      message: "Missing required query params: owner, repo",
    });
  }

  // 2) Always send auth
  const url = `https://api.github.com/repos/${owner}/${repo}/issues?state=open&per_page=100`;

  const ghRes = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "gitbounty-vercel-api",
    },
  });

  // 3) Fail hard on auth/rate/permissions problems
  if (!ghRes.ok) {
    const text = await ghRes.text().catch(() => "");
    const status = ghRes.status;

    // Helpful diagnostics to bubble up
    const diagnostic = {
      ok: false,
      error:
        status === 401
          ? "GITHUB_TOKEN_INVALID"
          : status === 403
          ? "GITHUB_FORBIDDEN_OR_RATE_LIMIT"
          : "GITHUB_REQUEST_FAILED",
      message: `GitHub API responded with ${status} ${ghRes.statusText}`,
      githubStatus: status,
      // These headers are super useful when debugging 403/rate issues
      rateLimit: {
        limit: ghRes.headers.get("x-ratelimit-limit"),
        remaining: ghRes.headers.get("x-ratelimit-remaining"),
        reset: ghRes.headers.get("x-ratelimit-reset"),
      },
      // Expose a small snippet (avoid dumping huge HTML)
      bodySnippet: text.slice(0, 400),
    };

    // Choose whether you want 500 or passthrough status:
    // - passthrough keeps it explicit (401/403)
    // - 500 makes it obvious "server misconfigured"
    return res.status(status).json(diagnostic);
  }

  const issues = await ghRes.json();

  return res.status(200).json({
    ok: true,
    issues,
  });
}
