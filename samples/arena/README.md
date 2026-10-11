# Star Race

Walk into stars: socket-free practice or separate players competing on an
authoritative server. See the [run guide](../../docs/apps/arena.md).
Generic ECS and transport are libraries; game rules and UI stay here.

```powershell
.\build\Release\arena_game.exe --solo
# Versus: keep the server running, then start clients in separate terminals.
.\build\Release\arena_server.exe --port 7777
.\build\Release\arena_game.exe 7777
```
