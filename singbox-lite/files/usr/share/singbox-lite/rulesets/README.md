# Bundled rule sets

These `.srs` files are generated data from:

- https://github.com/SagerNet/sing-geosite (GPL-3.0)
- https://github.com/SagerNet/sing-geoip (GPL-3.0)

See `LICENSE.sing-geosite` and `LICENSE.sing-geoip` in this directory. The
LuCI application only redistributes these generated rule sets together with
the GPL-3.0-or-later source of singbox-lite; see the repository LICENSE.

Files are intentionally small and are used with sing-box `type: local` rule
sets so the core never has to download rule data at startup.
