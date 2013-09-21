redis = require "redis"
http = require "http"
zlip = require "zlib"
util = require "util"
path = require "path"
fs = require "fs"
Log = require("log")
log = new Log("notice");

class Serve
  constructor: (options) ->
    @dir = path.resolve(options.dir ? process.cwd()) + path.sep
    @port = options.port ? 3000

    validmounts = (mount for mount in options.mounts when mount.path? and (typeof mount.handler == "function" or typeof mount.handler == "string"))
    @regexmounts = (mount for mount in validmounts when util.isRegExp mount.path)

    @mounts = []
    for mount in validmounts when typeof mount.path == 'string'
      @mounts[mount.path] = mount.handler

    @cache = {}

    @server = http.createServer @handler
    @server.listen @port, =>
      log.notice "serving " + @dir + " on port "+@port

  handler: (req, res) =>
    addr = req.socket.remoteAddress + ":" + req.socket.remotePort
    url = req.url
    log.info addr, "wants "+url

    # check for direct mounts
    handler = @mounts[url]
    if handler?
      log.debug "direct handler " + url
      if typeof handler == "function"
        handler req, res
        return
      else
        # handler is a string defining an alias
        url = handler

    # test all the regexes
    for mount in @regexmounts
      if mount.path.test url
        log.debug "direct regex handler " + mount.path
        if typeof mount.handler == "function"
          mount.handler req, res
          return
        else
          # handler is a string defining an alias
          url = mount.handler

    #TODO look in redis cache
    if @cache[url]?
      log.debug "from cache: " + url
      res.end @cache[url]
      return

    # load file from disk, cache it
    localpath = (path.resolve @dir, url[1..])
    if 0 isnt localpath.indexOf @dir
      log.debug "403 request for " + localpath + " is not in " + @dir
      res.writeHead 403, "Access Denied"
      res.end "403 Access Denied"
      return
    if fs.existsSync localpath
      log.debug "loading "+localpath
      file = @load_and_cache localpath, url
      res.end file
      return

    # nope.
    log.info "404 " + url + " not found at "+localpath
    res.writeHead 404, "File not found"
    res.end "404 File not found"

  load_and_cache: (path, url) =>
    content = fs.readFileSync path
    #TODO cache this in redis
    @cache[url] = content
    return content

module.exports = Serve
