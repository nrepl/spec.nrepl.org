# nREPL Protocol Spec

This repository contains the documentation for the nREPL protocol. In
order to avoid breaking existing links, the top-level nrepl.org domain
documents the original Clojure server implementation, and all the
general cross-language details are meant to go here.

## Site generation

The site at https://spec.nrepl.org is generated from `spec.md` using
[pandoc](https://pandoc.org), with `_head.html` and `_foot.html`
wrapping the rendered body. Run `make` to build `index.html` locally.

A GitHub Actions workflow (`.github/workflows/pages.yml`) rebuilds and
deploys to GitHub Pages on every push to `main`.

## License

Except where otherwise noted, nrepl.org is licensed under the Creative
Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0).
