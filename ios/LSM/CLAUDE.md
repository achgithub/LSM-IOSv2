# Review checklist

- [ ] Traced every computed `var` in touched SwiftUI views for per-render cost (loops/parsing over collections); cached anything expensive in `@State` invalidated only on its real trigger — checked against full-season data, not demo data.
