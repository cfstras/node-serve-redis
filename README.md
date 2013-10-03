node-serve-redis
================

a caching, static, redis-backed HTTP file server, built with node.js

for an example on how to use, see [bin/serve.coffee](bin/serve.coffee).

features
--------

- gzip content encoding (if filesize benefits)
- browser-side caching via ETags (md5 of content)
- redis-backed caching of files
- plain-javascript-object fallback cache
- routing via alias or regex
- "mounts" for custom handler functions

license
-------
**MIT License**.
For details, see [LICENSE](LICENSE)
