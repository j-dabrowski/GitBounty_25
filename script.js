// Chainlink Functions source for RaffleWithFunctions
//
// Solidity passes:
// args[0] = repo_owner  (e.g. "chainlink")
// args[1] = repo        (e.g. "functions-hardhat-starter-kit")
// args[2] = issueNumber (e.g. "12")
//
// The script:
// - Searches for a PR in the repo whose title or body contains this issue number
// - Checks "merged_at" for whether the PR is merged into "main"
// - If found, returns the PR author's GitHub username as a UTF-8 string
// - Otherwise returns "not_found"

const owner = args[0];
const repo = args[1];
const issueNumber = args[2];

// Load GitHub token from remote secrets (Amazon S3-secured JSON, e.g. { "apiToken": "ghp_..." })
if (!secrets.apiKey) {
  throw Error("Missing secret: apiToken");
}
const githubToken = secrets.apiKey;

// Build GitHub search API query for PRs referencing this issue number
const query = `repo:${owner}/${repo} type:pr #${issueNumber} in:title,body`;
const url = `https://api.github.com/search/issues?q=${encodeURIComponent(query)}`;

// Search for matching PR(s)
const response = await Functions.makeHttpRequest({
  url,
  headers: {
    Authorization: `Bearer ${githubToken}`,
    Accept: "application/vnd.github+json",
    "User-Agent": "chainlink-functions-github-script"
  }
});

// If the search request fails, treat as "not_found" (soft fail)
if (response.error) {
  return Functions.encodeString("not_found");
}

const results = response.data;
if (!results || !results.items || results.items.length === 0) {
  return Functions.encodeString("not_found");
}

// For each candidate PR:
// - ensure it's actually a PR
// - fetch full PR details
// - check it's merged into "main"
// - return the author's login (GitHub username)
for (const item of results.items) {
  if (!item.pull_request || !item.pull_request.url) continue;

  const prResponse = await Functions.makeHttpRequest({
    url: item.pull_request.url,
    headers: {
      Authorization: `Bearer ${githubToken}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "chainlink-functions-github-script"
    }
  });

  if (prResponse.error) continue;

  const pr = prResponse.data;

  if (
    pr &&
    pr.merged_at &&        // must be merged
    pr.base &&
    pr.base.ref === "main" && // merged into main
    pr.user &&
    pr.user.login          // author username
  ) {
    // This username is what fulfillRequest() will look up in s_githubToAddress
    return Functions.encodeString(pr.user.login);
  }
}

// If we reach here, nothing matched the criteria
return Functions.encodeString("not_found");
