# comicmeta.koplugin

Plugin for KOReader to extract metadata from .cbz and .cbr files as Custom Metadata

Metadata should be stored in a ComicInfo.xml at the root of the archive, as specified by [The Anansi Project](https://anansi-project.github.io/docs/category/schemas).

## Example

https://github.com/user-attachments/assets/dbedf7fa-b5df-4536-8686-919342ff41ce

## Contributing

### Running Test

To run test, you can run `make` in the root dir of the project.

```shell
❯ make
LUA_PATH="./?.lua;./lib/?.lua;" busted .
●●●●●●
6 successes / 0 failures / 0 errors / 0 pending : 0.002076 seconds
```

To run test, [busted](https://github.com/lunarmodules/busted) is used.
