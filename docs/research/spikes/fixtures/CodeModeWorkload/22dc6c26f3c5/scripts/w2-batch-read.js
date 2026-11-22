const found = JSON.parse(await tools.code_search({ query: "TODO(memoshi)", path: "Sources", maxResults: 10 }));
const paths = found.matches.map((match) => match.path);
const [texts, outline] = await Promise.all([
	Promise.all(paths.map((path) => tools.file_read({ path }))),
	tools.symbols_outline({ paths }).then((value) => JSON.parse(value)),
]);
const pattern = /^\/\/ TODO\(memoshi\): item (\d{2})-(\d{4}) review needed\.$/gm;
let bytes = 0;
let todos = 0;
let lineSum = 0;
const perFile = [];
for (const text of texts) {
	bytes += text.length;
	let count = 0;
	for (const match of text.matchAll(pattern)) {
		count += 1;
		lineSum += Number(match[2]);
	}
	todos += count;
	perFile.push(count);
}
const symbols = outline.files.reduce((total, file) => total + file.symbols, 0);
return JSON.stringify({
	files: texts.length,
	bytes,
	todos,
	lineSum,
	perFile,
	symbols,
	first: outline.files[0].firstSymbol,
	last: outline.files[outline.files.length - 1].lastSymbol,
});
