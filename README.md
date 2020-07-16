# KeyDB overlay

This overlay contains ebuilds for [KeyDB](https://github.com/JohnSully/KeyDB). They were created from `dev-db/redis::gentoo` ebuilds, but they do not contain OpenRC, SystemD nor logrotate support. Pull requests with fixes and new features are welcome.

## How to install

Copy [`keydb.conf`](keydb.conf) to `/etc/portage/repos.conf`.
