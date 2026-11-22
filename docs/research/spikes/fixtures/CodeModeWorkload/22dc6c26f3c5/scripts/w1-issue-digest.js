const repo = "memoshi/fixture";
const list = JSON.parse(await tools.issues_list({ repo, state: "open", limit: 4 }));
const texts = await Promise.all(list.items.map((item) => tools.issue_get({ repo, number: item.number })));
const issues = texts.map((value) => JSON.parse(value));
issues.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0));
const rows = issues.map((issue) => {
	const lines = issue.body.split("\n");
	const tasks = lines.filter((line) => line.startsWith("- ["));
	const done = tasks.filter((line) => line.startsWith("- [x]")).length;
	const words = issue.body.split(/\s+/).filter((word) => word.length > 0).length;
	return { n: issue.number, labels: issue.labels.join(","), words, tasks: `${done}/${tasks.length}`, comments: issue.comments };
});
return JSON.stringify({ repo, count: rows.length, rows });
