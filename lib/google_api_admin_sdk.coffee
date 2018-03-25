quest    = require 'quest'
dotty    = require 'dotty'
_        = require 'underscore'
_.str    = require 'underscore.string'
retry    = require 'retry'


# base google api class. provides functions for:
# static methods for:
# 1. Generating an initial oauth redirect with scopes you want
# 2. Trading in authorization codes for tokens
# class object is instantiated with oauth token info

class GoogleAPIAdminSDK
  constructor: (@options) ->
    throw new Error('Must initialize GoogleAPI with token info') unless @options.token
    throw new Error('Must provide either a refresh token or an access token') unless @options.token.refresh or @options.token.access
    # client secret needed for auto-refresh
    throw new Error('If providing a refresh token, must provide client id and secret') unless not @options.token.refresh or (@options.client?.id and @options.client?.secret)

  retry_options: {maxTimeout: 3 * 60 * 1000, retries: 5, randomize: true}
  @retry_err: (err, resp) ->
    return err if err?
    # 500/502 = "backend error"
    # 403/503 = rate limiting errors
    # 404
    # 412
    if resp.statusCode in [403, 404, 412, 500, 502, 503]
      return new Error "Status code #{resp.statusCode} from Google"
    return null

  # default response interpreters--APIs should most likely specialize these
  # error_handler returns true if it found/handled an error
  @error_handler: (cb) ->
    (err, resp, body) ->
      return cb(err) or true if err
      unless 200 <= resp.statusCode < 299
        return cb(
          code: resp.statusCode
          body: body
          req: _(resp?.req or {}).chain().pick('method', 'path', '_headers').extend({body:"#{resp?.req?.res?.request?.body}"}).value()
        ) or true
      return false
  @response_handler: (cb) ->
    (err, resp, body) ->
      return cb err, body if err?
      return cb null, {'204': 'Operation success'} if resp.statusCode is 204
      return cb body, null if resp.statusCode >= 400
      handle_entry = (entry) ->
        obj = { id: entry.id.$t, updated: entry.updated.$t, link: entry.link, title: entry.title?.$t, feedLink: entry.gd$feedLink, who: entry.gd$who }
        _(entry).chain().keys().filter((k) -> k.match /^apps\$/).each (apps_key) ->
          key = apps_key.match(/^apps\$(.*)$/)[1]
          if key is 'property'
            obj[prop.name] = prop.value for prop in entry[apps_key]
          else
            obj[key] = entry[apps_key]
        obj
      if body?.feed?
        return cb null, { id: body.feed.id, link: body.feed.link, data: _(body.feed.entry or []).map(handle_entry) }
      else if body?.entry
        return cb null, handle_entry(body.entry)
      else if _.str.include(body?.kind, 'admin#directory')
        return cb null, body
      else if resp.statusCode is 200 # catch all for success

        return cb null, body
      else
        console.warn 'WARNING: unhandled body', resp.statusCode, body
        return cb null, body

  @request_token: (options, cb) =>
    # need code, client.id, client.secret
    for required in ['code', 'redirect_uri', 'client.id', 'client.secret']
      if not dotty.exists(options, required)
        return cb new Error("Error: '#{required}' is necessary to request a token")
    options =
      method: 'post'
      uri: 'https://accounts.google.com/o/oauth2/token'
      json: true
      form:
        code          : options.code
        redirect_uri  : options.redirect_uri
        client_id     : options.client.id
        client_secret : options.client.secret
        grant_type    : 'authorization_code'
    operation = retry.operation @retry_options
    operation.attempt =>
      quest options, (err, resp, body) =>
        unless operation.retry GoogleAPIAdminSDK.retry_err(err, resp)
          (@response_handler(cb)) err, resp, body

  request_refresh_token: (cb) =>
    options =
      method: 'post'
      uri: 'https://accounts.google.com/o/oauth2/token'
      json: true
      form:
        refresh_token : @options.token.refresh
        client_id     : @options.client.id
        client_secret : @options.client.secret
        grant_type    : 'refresh_token'
    operation = retry.operation @retry_options
    operation.attempt =>
      quest options, (err, resp, body) =>
        return if operation.retry GoogleAPIAdminSDK.retry_err(err, resp)
        @options.token.access = body.access_token if body.access_token?
        @options.token.id = body.id_token if body.id_token?
        console.warn 'Failed to refresh Google token!' if resp.statusCode isnt 200
        (GoogleAPIAdminSDK.response_handler(cb)) err, resp, body

  oauth2_request: (options, refreshed_already, cb) =>
    if _(refreshed_already).isFunction()
      cb = refreshed_already
      refreshed_already = false

    refresh = () =>
      @request_refresh_token (err, body) =>
        return cb err, null, body if err
        @oauth2_request options, true, cb
    return refresh() unless @options.token.access
    options.headers = {} unless options.headers
    _(options.headers).extend { Authorization: "Bearer #{@options.token.access}" }
    operation = retry.operation @retry_options
    operation.attempt =>
      quest options, (err, resp, body) =>
        # 401 means invalid credentials so we should refresh our token.
        # But, if we refreshed_already, then we genuinely have invalid credential problems.
        if not refreshed_already and resp?.statusCode is 401 and @options.token.refresh
          return refresh()
        # keep retrying until there is no err and resp.statusCode is not an error code
        unless operation.retry GoogleAPIAdminSDK.retry_err(err, resp)
          cb err, resp, body

  tokeninfo: (cb) =>
    operation = retry.operation @retry_options
    operation.attempt =>
      quest
        uri: 'https://www.googleapis.com/oauth2/v1/tokeninfo'
        qs: { access_token: @options.token.access }
      , (err, resp, body) =>
        unless operation.retry GoogleAPIAdminSDK.retry_err(err, resp)
          (GoogleAPIAdminSDK.response_handler(cb)) err, resp, body

module.exports = GoogleAPIAdminSDK
