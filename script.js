const owner = args[0];
const repo = args[1];
const issueNumber = args[2];

const github = "";
const query = `repo:${owner}/${repo} type:pr #${issueNumber} in:title,body`;
const url = `https://api.github.com/search/issues?q=${encodeURIComponent(query)}`;

const response = await Functions.makeHttpRequest({
  url,
  headers: {
    "Authorization": `Bearer ${github}`,
    "Accept": "application/vnd.github+json"
  }
});

if (response.error) {
    return Functions.encodeString("not_found");
}

const results = response.data;

if (!results || !results.items || results.items.length === 0) {
  return Functions.encodeString("not_found");
}

// Now check each PR to see if it was merged into main
for (const item of results.items) {
  if (!item.pull_request || !item.pull_request.url) continue;

  const prResponse = await Functions.makeHttpRequest({
    url: item.pull_request.url,
    headers: {
      "Authorization": `Bearer ${github}`,
      "Accept": "application/vnd.github+json"
    }
  });

  if (prResponse.error) continue;

  const pr = prResponse.data;

  if (
    pr &&
    pr.merged_at &&
    pr.base &&
    pr.base.ref === "main" &&
    pr.user &&
    pr.user.login
  ) {
    return Functions.encodeString(pr.user.login);
  }
}

return Functions.encodeString("not_found");
