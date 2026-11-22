await tools.probe_mark({ phase: "loop" });
let state = 1;
for (;;) {
	state = (state * 48271) % 2147483647;
}
