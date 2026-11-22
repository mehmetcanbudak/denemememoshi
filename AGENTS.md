# Memoshi agent entrypoint

## Project context

Start with [the handoff's reading order](docs/HANDOFF.md#1-read-in-this-order). The accepted decisions and relevant plan/spec govern the work; research and external examples do not silently amend them. Existing build/check entrypoints are in [README](README.md#build-and-test).

## Task guidance on demand

Before implementing, reviewing, debugging or testing native code, changing build/security/distribution settings, localizing UI, investigating a design/reference app, or authoring agent-facing instructions, consult the [development-skill routing table](docs/skills.md#routing). Read the matching source entrypoint and only its relevant references, not the whole catalogue.

The catalogue distinguishes preferred guidance, optional supplements, tool-gated workflows, license-gated references and excluded integrations. Its qualified IDs are source labels, not registered tool/agent names. Check the selected entry's lookup, prerequisites and known corrections before applying it. Follow the current host's available tools and authorization rules; a listed skill does not install tools or authorize scripts, services, instrumentation or configuration changes.
