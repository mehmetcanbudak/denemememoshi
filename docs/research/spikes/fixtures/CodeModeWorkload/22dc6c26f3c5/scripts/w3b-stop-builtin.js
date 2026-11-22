const values = Array.from({ length: 262144 }, (_, index) => (index * 2654435761) % 1000003);
await tools.probe_mark({ phase: "builtin" });
values.sort();
return values.length;
