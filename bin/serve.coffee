Serve = require "../serve"

options =
  https: false
  port: 3000
  dir: process.cwd() + "/../_site"
  redis: {
    host: "localhost"
    port: 6379
    password: null
    prefix: "serve:"
  }
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

server = new Serve options