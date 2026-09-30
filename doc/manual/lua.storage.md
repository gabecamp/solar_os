+++
id = "lua.storage"
title = "Lua storage and files API"
section = "api"
summary = "Storage and files: storage"
keywords = "lua solaros api storage storage"
packages_any = ["app_lua"]
agent_reference_sections = true
+++
# Lua storage and files API

[API overview](lua.md) · [Python storage and files](python.storage.md)

## `solaros.storage`

- `solaros.storage`: `status`, `is_mounted`, `mount`, `unmount`, `mount_point`,
  `usage`, `resolve`, `stat`, `exists`, `scandir`, `read_file`, `write_file`, `rescan`,
  `blocks`, `block_count`, `block`, `usage_for_block`, `mkdir`, `makedirs`,
  `rmdir`, `remove`, `rename`, `copy`, `mount_volume`, `unmount_volume`

`stat(path)` returns `type`, `is_file`, `is_dir`, `size`, `mtime`, and `mode`.
`scandir(path[, cursor[, limit]])` returns an `entries` table and a numeric
`next_cursor`, which is absent at the end. The default page size is 32 and the
maximum is 128. Directory cursors are offsets into the current enumeration;
restart without a cursor if the directory changes between calls.

`read_file(path[, max_bytes])` returns up to `max_bytes` bytes (default 4096,
at most 65536) as a binary-safe string. `write_file(path, data[, append])`
writes the string `data` (at most 65536 bytes). Without `append` the file is
replaced atomically: the data is written and synced to `<path>.tmp`, which
then replaces `path`, so a failure never leaves a truncated file. With
`append` true the bytes are added to the end and the file is created if
missing. The parent directory must exist (see `makedirs`).

```lua
local storage = solaros.storage
storage.makedirs("/sdcard/games")
storage.write_file("/sdcard/games/save.txt", "day=3\nhp=71\n")
print(storage.read_file("/sdcard/games/save.txt"))
```

`makedirs(path[, exist_ok])` creates missing parents. `exist_ok` defaults to
`true`.

## Quick reference

Use `solaros.storage` for storage and files.
See `man lua` for runtime conventions and service availability.
