# Bookkeeper

A World of Warcraft: Forever addon that saves the text of every book you read in the world, so you can read it later — somewhere safer than the middle of a hostile zone — on any character.

## Features

- **Automatic capture.** Open a book and the addon flips through every page, saves the text, and returns you to page 1. It records where and when you found it.
- **Account-wide library.** Books found on one character can be read on all of them.
- **Collections tab.** Adds a **Books** tab to the Collections window (Shift-P), alongside Pet Journal and Appearances. Also available as a standalone window with `/bk`.
- **Faithful reader.** Pages are shown with the original parchment, stone or metal backgrounds and fonts. Read as a single scrolling page (default) or in the original pages, turning pages with the mouse wheel.
- **Search** by title, text, or the zone where a book was found.
- **New-book glow** on books you haven't opened in the library yet.
- **Books only by default.** Plaques, gravestones and monuments are skipped unless you turn them on with `/bk plaques`; they then appear in their own section.

## Commands

| Command | Description |
|---|---|
| `/bk` | Open the library window |
| `/bk list` | List saved books in chat |
| `/bk read <number>` | Print a saved book to chat |
| `/bk plaques` | Toggle saving plaques, graves and monuments |
| `/bk debug` | Toggle debug messages |
| `/bk wipe confirm` | Delete all saved books (all characters) |

## Notes

- Forever's "library books" (the ones you turn in to a librarian) are quest items with no readable text, so they aren't collected.
- Saved data is written by the game on logout or `/reload`; a client crash loses anything captured since the last one.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager). Push a version tag (for example `v0.5.0`) and the GitHub Action packages the addon and uploads it to CurseForge and GitHub Releases. The action needs a `CF_API_KEY` repository secret containing a CurseForge API token, and the TOC needs an `## X-Curse-Project-ID:` line.

## License

[MIT](LICENSE)
