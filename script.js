const owner = "j-dabrowski";
const repo = "Test_Repo_2025";
const issueNumber = 1;

const url = "https://api.github.com/repos/" + owner + "/" + repo + "/issues/" + issueNumber;

const response = await Functions.makeHttpRequest({ url });

if (response.error) {
  throw Error("GitHub request failed");
}

const issue = response.data;

if (!issue || !issue.state) {
  return Functions.encodeString("not_found");
}

return Functions.encodeString(issue.state);