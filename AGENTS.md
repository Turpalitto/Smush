# Working context for SLIME RUSH

- Work in `arena/6d0cda1c-smush` for this task. Keep changes in this branch unless the owner changes the target.
- The primary product is the native offline Godot game at the repository root. `web/` is a secondary implementation retained from the uploaded archive.
- The owner's current priority is the game itself: controls, absorption/growth, mutation choices, enemies, boss combat, run pacing, visuals and sound.
- Advertising, purchases, analytics expansion, Android SDK setup, signing and store publication are deferred. Preserve existing code; do not make these the next task or a blocker for gameplay work. Return to them when the owner asks.
- Read `PROGRESS.md`, `DEVELOPMENT_PLAN.md` and `GAMEPLAY_STATUS.md` for current state. `docs/history/` and `web/docs/` are historical, not current instructions or proof of completion.
- Native QA: `./scripts/run_qa.sh`. For relevant gameplay changes also verify the PCK using `tools/build_pck.py` and the test scene from outside the source directory.
- The last recorded source/PCK runs passed 286 assertions. Report newly executed checks accurately; do not equate automated phase transitions/UI sizing with a full human playthrough, visual review or measured Android FPS.
- Keep the gameplay status and test report consistent with actual changes. Do not declare all development stages complete while manual game-quality checks remain outstanding.
