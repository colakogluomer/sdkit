# Homebrew distribution

This repository is its own Homebrew **tap**: `Formula/sdkit.rb` is committed here. The formula installs the whole kit into
brew's `libexec` and links one command, `sdkit`. There is no separate tap repository (a tap is any git repo with a `Formula/`
directory; the `homebrew-` name prefix only matters for the short `brew tap user/repo` form, and we give the URL).

## For developers
```
brew tap wecii/sdkit https://github.com/wecii/sdkit.git                       # once
brew trust wecii/sdkit                                                   # once; recent Homebrew refuses formulae from untrusted taps
brew install sdkit                                                            # brings jq and node
brew upgrade sdkit                                                            # later
```
Then, in a repo (one person, once): `sdkit init`. Every other developer just clones. `sdkit doctor` checks a repo,
`sdkit upgrade` brings a repo up to the installed kit version after a `brew upgrade`.

The git hook shims (`.githooks/`) find the installed kit by running `sdkit where`, so nothing has to be registered on the
machine and brew upgrades do not break them.

Until the first release is tagged the formula has only a `head` block: `brew install --HEAD sdkit` builds `master`.

## For maintainers: every release
0. Run `packaging/scan-publishable.sh --history` (no hard findings, and read the soft ones: identities, names, paths).
1. Merge to `master`, bump the version in `.claude-plugin/plugin.json` (and `marketplace.json`).
2. Tag the release commit and push the tag: `git tag v<version> <commit> && git push origin v<version>`.
3. Regenerate the formula from that tag (it pins tag and revision): `packaging/homebrew/gen-formula.sh --write`.
4. Commit `Formula/sdkit.rb` on `master` and push. Developers get it with `brew update && brew upgrade sdkit`.
   (The formula commit comes after the tag, so the tag never contains its own revision; this is expected.)

Try an unreleased branch before merging, without touching your real brew setup more than needed: generate into a throwaway
clone with `gen-formula.sh --head-only --head-branch <branch> --repo-url file:///path/to/bare-clone.git --write`, tap that
clone (`brew tap you/test file:///...`), `brew trust` it, `brew install --HEAD you/test/sdkit`, then `brew uninstall` and `brew untap`.

## Notes
- `using: :git` is in the formula on purpose: brew does not recognise an ssh URL (`git@host:path`) or a `file://` URL as a
  git repository and would download it as a file.
- The repo is private, so brew clones over SSH with the developer's own key; no credentials are in the formula.
- brew installs `node` because OpenSpec (the spec engine) is an npm package. The OpenSpec CLI itself is installed by
  `sdkit init --install-openspec`, not by brew.
- Windows is out of scope (the kit is bash).
