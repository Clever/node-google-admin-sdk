node_url    = require('url')
_           = require 'underscore'
_.str       = require 'underscore.string'
_.mixin(_.str.exports())
{Readable}  = require 'stream'

# General auto-pagination of feeds. Assumes feed responses of the form
# { data: [...] link: [ { rel: ..., href: }]}
# or singular resource responses of the form
# { data: {} }
class QueryStream extends Readable
  constructor: (@_query) ->
    super { objectMode: true }
    @running = false

  _read: () => @run()

  run: () =>
    return if @running
    @running = true
    @_query.exec (err, obj) =>
      return @emit('error', err) if err?
      return @emit('error', "Cannot stream object #{JSON.stringify(obj, null, 2)}") unless obj?.kind?
      resource = _.strRightBack(obj.kind, '#')
      if _(obj?[resource]).isArray()
        @push r for r in obj[resource]
      else if obj?
        @push obj
      if not obj.nextPageToken
        @push null
        return
      if obj.nextPageToken
        parsed = node_url.parse(@_query._opts.uri)
        if parsed.search.indexOf('pageToken') != -1
          new_search = "?pageToken=#{obj.nextPageToken}&#{_(parsed.search).strRight('&')}"
        else
          new_search = "?pageToken=#{obj.nextPageToken}&#{parsed.search.slice(1)}"
        @_query._opts.uri = "#{parsed.protocol}//#{parsed.host}#{parsed.pathname}#{new_search}"
      @running = false
      process.nextTick @run

class Query
  constructor: (@_google_api, @_opts) ->
  exec: (cb) =>
    @_google_api.oauth2_request @_opts, @_google_api.constructor.response_handler(cb)
  stream: () => new QueryStream @

module.exports =
  Query: Query
  QueryStream: QueryStream
