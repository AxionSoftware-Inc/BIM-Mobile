## BIM-Mobile change checklist

- [ ] Modeling changes are covered by a native/API test.
- [ ] Render semantic changes update the versioned RenderScene contract before viewport code.
- [ ] Viewport changes only project engine-owned scene data; they do not rebuild BIM geometry.
- [ ] Wall/opening changes pass `bash tools/run_wall_opening_smoke.sh`.
- [ ] `bash tools/check_architecture.sh`, formatting, analysis and relevant tests pass.
