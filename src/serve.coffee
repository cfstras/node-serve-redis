redis = require "redis"
http = require "http"
https = require "https"
zlip = require "zlib"
util = require "util"
path = require "path"
fs = require "fs"
crypto = require "crypto"
redis = require "redis"
zlib = require "zlib"
liblog = require "log"
log = new liblog "notice"

md5 = (data) ->
  return crypto.createHash('md5').update(data).digest("hex")

getContentType = (uri) ->
  ext = path.extname(uri).toLowerCase()
  switch ext
    when ".htm", ".html" then "text/html; charset=utf-8"
    when ".css" then "text/css"
    when ".js" then "application/javascript"
    when ".png" then "image/png"
    when ".gif" then "image/gif"
    when ".ico" then "image/x-icon"
    when ".swf" then "application/x-shockwave-flash"
    when /^\..+$/.test ext then "application/octet-stream"
    else "text/plain"

class Serve
  constructor: (options, callback) ->
    @dir = path.resolve(options.dir ? process.cwd()) + path.sep
    @port = options.port ? 3000

    log = new liblog(options.loglevel ? "notice")

    @errors = options.errors ? {}

    if options.mounts?
      validmounts = (mount for mount in options.mounts when mount.path? and (typeof mount.handler == "function" or typeof mount.handler == "string"))
      @regexmounts = (mount for mount in validmounts when util.isRegExp mount.path)
    else
      log.warning "no mounts defined"
      validmounts = []
      @regexmounts = []

    @mounts = []
    for mount in validmounts when typeof mount.path == 'string'
      @mounts[mount.path] = mount.handler

    if options.redis?
      host = options.redis.host ? "localhost"
      port = options.redis.port ? 6379
      @redis = redis.createClient port, host, {return_buffers: true}
      @prefix = options.redis.prefix ? ""
      if options.redis.password?
        @redis.auth options.redis.password
      log.notice "using redis at " + host+":"+port
    else
      log.warning "using local in-memory cache, no redis option given"
      @cache = {}

    if options.https? and options.https.key? and options.https.cert?
      @server = https.createServer options.https, @handler
    else
      @server = http.createServer @handler
    @server.on "listening", =>
      log.notice "serving " + @dir + " on port "+@port
      typeof callback == "function" && callback()
    @server.on "error", (err) =>
      log.error "server error" + err
    @server.listen @port

  handler: (req, res) =>
    addr = req.socket.remoteAddress + ":" + req.socket.remotePort
    url = req.url
    log.info addr, "wants "+url
    @serve req, res, url

  serve: (req, res, url) =>
    splits = url.split("?")
    urlNoQuery = splits[0]
    query = if splits[1]? then "?"+splits[1] else ""

    # check for direct mounts
    handler = @mounts[urlNoQuery]
    if handler?
      log.debug "direct handler " + urlNoQuery
      if typeof handler == "function"
        handler req, res
        return
      else
        # handler is a string defining an alias
        url = handler + query
        urlNoQuery = handler

    # test all the regexes
    for mount in @regexmounts
      if mount.path.test url or mount.path.test urlNoQuery
        log.debug "direct regex handler " + mount.path
        if typeof mount.handler == "function"
          mount.handler req, res
          return
        else
          # handler is a string defining an alias
          url = mount.handler

    # ok, there are no dynamic handlers. drop the query string
    url = urlNoQuery

    # look in redis cache
    if @redis?
      @redis.hgetall @prefix+"meta:"+url, (err, headers) =>
        if err?
          log.error "could not get "+url+": " + err + ";" + headers
          res.writeHead 500, "Internal Server Error"
          res.end "500 Internal Server Error"
          return
        if headers?
          headers.ETag = headers.ETag.toString()
          if req.headers["if-none-match"] == headers.ETag
              # File is cached in browser
              # Response: 304 Not Modified
              res.writeHead 304, {"ETag": headers.Etag, "Vary": "Accept-Encoding"}
              res.end()
            else
              # get blob
              @redis.get @prefix+"blob:"+headers.ETag, (err, content) =>
                if err?
                  log.error "could not get "+headers.ETag+": " + err + ";" + content
                  res.writeHead 500, "Internal Server Error"
                  res.end "500 Internal Server Error"
                  return
                res.writeHead 200, headers
                res.end content
        else # reply was null == file is not cached
          @load_and_serve url, req, res
      return
    else
      if @cache.hasOwnProperty url
        file = @cache[url]
        if req.headers["if-none-match"] == file.headers.ETag
          # File is cached in browser
          # Response: 304 Not Modified
          res.writeHead 304, {"ETag": file.headers.Etag, "Vary": "Accept-Encoding"}
          res.end()
        else
          log.debug "from cache: " + url
          res.writeHead 200, file.headers
          res.end file.content
      else
        @load_and_serve url, req, res

  load_and_serve: (url, req, res) =>
    # load file from disk, cache it
    localpath = (path.resolve @dir, url[1..])
    if 0 isnt localpath.indexOf @dir
      log.debug "403 request for " + localpath + " is not in " + @dir
      res.writeHead 403, "Access Denied"
      res.end "403 Access Denied"
      return
    if fs.existsSync localpath
      log.debug "loading "+localpath
      file = @load_and_cache localpath, url, (err, headers, content) =>
        if !err and headers? and content?
          res.writeHead 200, headers
          res.end content
        else
          @err404 url, localpath, req, res
      return
    else
      @err404 url, localpath, req, res

  err404: (url, localpath, req, res) =>
    log.notice "404 " + url + " not found at "+localpath
    res.writeHead 404, "File not found"
    if @errors.hasOwnProperty(404) and @errors[404] != url
      @serve req, res, @errors[404]
    else
      res.end "404 File not found"

  load_and_cache: (localpath, url, callback) =>
    if fs.statSync(localpath).isDirectory()
      localpath += path.sep+'index.html'
    fs.readFile localpath, (err, content) =>
      if err?
        log.error "loading " + localpath + ": " + err
        callback err, null, null
        return
      headers =
          "Content-Type": getContentType localpath
          "Vary": "Accept-Encoding"

      zlib.gzip content, (err,gzipped) =>
        if gzipped.length < content.length
          content = gzipped
          headers["Content-Encoding"] = "gzip"

        tag = md5 content
        headers["Content-Length"] = content.length
        headers["ETag"] = tag

        if @redis?
          @redis.hmset @prefix+"meta:"+url, headers, (err) =>
            if err?
              log.error "could not cache meta "+url+": " + err
              return
            @redis.set @prefix+"blob:"+tag, content, (err) =>
              if err?
                log.error "could not cache blob "+url+" "+tag+": " + err
          callback err, headers, content
        else
          @cache[url] = {headers: headers, content: content}
          callback err, headers, content

module.exports = Serve
