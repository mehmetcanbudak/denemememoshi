await tools.probe_mark({ phase: "memory" });
const chunks = [];
for (let index = 0; ; index += 1) {
	chunks.push("x".repeat(1048576) + index);
}
