# Arena

Local Goose ECS game with an authoritative TCP server, shared CLI/graphics
controller and optional gfx rendering. See the [run guide](../../docs/apps/arena.md).
Generic ECS and transport are libraries; game rules and UI stay here.

```text
python tools/arena.py --build build-core --demo --ticks 80
python tools/arena.py --build build --graphics
```
