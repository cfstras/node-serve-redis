Serve = require "../serve"
log = console.log.bind console

options =
  https: false
  port: 3000
  dir: process.cwd() + "/../_site"
  redis:
    host: "localhost"
    port: 6379
    password: null
    prefix: "serve:"
  errors:
    404: "/404/"
  mounts: [
    {
      path: "/derp"
      handler: (req, res) ->
        res.write "You have reached '/derp'!\n"
        res.write "Have a nice day!"
        res.end()
    }, {
      path: /\/dynamic\//
      handler: (req, res) ->
        res.write "You have reached dynamic!\n"
        res.write "Query: " + req.url
        res.end "\n"
    }, {
      path: "/"
      handler: "/index.html"
    }
  ]

test = ->
  server = new Serve options, (err) ->
    log "testing..."
    # ... run some tests
    log "ending..."
    server.server.close()
    server.redis && server.redis.quit()

test
