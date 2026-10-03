# Request: let Lua scripts write files (`solaros.storage.write_file`)

Text and details for a feature request / PR to the SolarOS author. The change
is commit "storage: add write_file for Lua and Python scripts" on
`gabecamp/solar_os` branch `claude/new-session-ws67f3`, also saved here as
`0001-storage-add-write_file-for-Lua-and-Python-scripts.patch`
(`git am` it onto the fork; on upstream it may need small fixes if the files
have moved on).

## The problem

Lua apps can read files but not write them. `solaros.storage` has
`read_file`, `mkdir`, `makedirs`, `remove`, `rename` and `copy`, but nothing
that puts bytes into a file. The Lua runtime doesn't load `io` or `os`
either (`src/apps/solar_os_lua.c`, the `luaL_requiref` list), so a Lua app
can't save any state: game saves, settings, high scores, logs. Python has
`open()`, so this only affects Lua.

## What the change adds

One function in the shared script API, for both Lua and Python:

```lua
solaros.storage.write_file(path, data[, append])
```

- `data` is a string (binary-safe), up to 64 KiB, the same limit as
  `read_file`.
- Without `append`, the file is **replaced atomically**. The bytes go to
  `<path>.tmp`, get synced, and then `solar_os_storage_replace_file()` (which
  already exists) swaps that in. A power cut or full card never leaves a
  half-written file.
- With `append = true`, the bytes are added to the end, and the file is
  created if it is missing.
- The parent directory must exist (use `makedirs`). Errors are raised like
  the other storage calls.

## Exactly what changes (9 files, +191 / -2)

| File | Change |
|---|---|
| `src/services/solar_os_storage.h` | `#define SOLAR_OS_STORAGE_WRITE_MAX_BYTES 65536U` and a declaration for `esp_err_t solar_os_storage_write_file(const char *path, const void *data, size_t len, bool append);` |
| `src/services/solar_os_storage.c` | New `storage_write_all()` (fwrite + `solar_os_storage_sync_file`) and `solar_os_storage_write_file()`. It validates the arguments (`ESP_ERR_INVALID_ARG`), the size (`ESP_ERR_INVALID_SIZE`) and that the path isn't a directory (`ESP_ERR_INVALID_STATE`). Append opens with `"ab"`. Replace writes the `.tmp` sibling via `solar_os_storage_sibling_path()`, then calls `solar_os_storage_replace_file(tmp, path, <path>.bak)`, and removes the `.tmp` on any error. |
| `src/apps/solar_os_lua.c` | `solua_storage_write_file()`: `solua_resolve_path` on arg 1, `luaL_checklstring` on arg 2, optional boolean arg 3, size check, `solua_check_esp(...)`. Picked up automatically by the API table through the `.inc` line below. |
| `src/apps/solar_os_python.c` | `solaros_storage_write_file()`: `mp_get_buffer_raise` (accepts `bytes`/`str`), optional append flag, `MP_DEFINE_CONST_FUN_OBJ_VAR_BETWEEN(..., 2, 3, ...)`. |
| `src/apps/solar_os_script_api.inc` | `SOLAR_OS_SCRIPT_API_FUNCTION(storage, write_file, write_file);` after `read_file`. |
| `doc/manual/lua.storage.md`, `doc/manual/python.storage.md` | Documents the call, with an example. |
| `tests/host/storage_mounts_test.c` | `assert_write_file()`: create, replace, append, binary data with NUL bytes, empty file, too big, bad arguments, directory path, missing parent. |
| `tests/test_script_binding_descriptor.py` | Script API count 766 → 767. |

## How it was checked

- `make storage_mounts_test` (host build of the storage service) passes,
  including the new write tests.
- The Python test suite: 400 pass. The 2 failures (FTP/SFTP) fail the same
  way without this change.
- **Not yet built with ESP-IDF or run on hardware**: the environment it was
  written in has no ESP-IDF. The first thing to do is build it and run a
  one-line Lua test on the device:
  `solaros.storage.write_file(solaros.storage.mount_point() .. "/t.txt", "hi")`.

## Suggested issue text

> **Lua apps can't write files**
>
> `solaros.storage` can read files but has no write call, and the Lua
> runtime doesn't load `io`, so Lua apps have no way to save state (games,
> settings). Would you accept a `storage.write_file(path, data[, append])` in
> the shared script API? It would mirror `read_file` (64 KiB limit,
> binary-safe) and replace the file atomically through the existing
> `solar_os_storage_replace_file()`, so a failed write never truncates the
> old file. I have a patch with host tests and manual pages and can open a
> PR.
