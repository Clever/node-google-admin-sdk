GoogleAPIAdminSDK = require "#{__dirname}/google_api_admin_sdk"
qs = require 'qs'
_         = require 'underscore'
dotty     = require 'dotty'
utils     = require "#{__dirname}/utils"
sanitize  = require 'sanitize-arguments'
{Query}   = require "#{__dirname}/query.coffee"
crypto    = require 'crypto'

class UserProvisioning extends GoogleAPIAdminSDK
  insert: (body, fields, cb) ->
    arglist = sanitize arguments, UserProvisioning.insert, [Object, String, Function]
    args = _.object ['body', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    return die "UserProvisioning::insert expected (Object body, [callback])" if not args.body?
    required = ['name.familyName', 'name.givenName', 'password', 'primaryEmail']
    for r in required
      if not dotty.exists(body, r)
        return die "UserProvisioning::insert requires '#{r}'"
    uri = "https://www.googleapis.com/admin/directory/v1/users"
    shasum = crypto.createHash 'sha1'
    shasum.update body.password
    body.password = shasum.digest 'hex'
    body.hashFunction = 'SHA-1'
    opts =
      method: 'post'
      uri: uri
      json: args.body
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  patch: (userkey, body, fields, cb) ->
    arglist = sanitize arguments, UserProvisioning.patch, [String, Object, String, Function]
    args = _.object ['userkey', 'body', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.userkey?
      return die "UserProvisioning::patch expected (String userkey, [Object body, String fields, callback])"
    uri = "https://www.googleapis.com/admin/directory/v1/users/#{args.userkey}"
    uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    opts = { method: 'patch', uri: uri, json: (args.body or true) }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  update: (userkey, body, fields, cb) ->
    arglist = sanitize arguments, UserProvisioning.patch, [String, Object, String, Function]
    args = _.object ['userkey', 'body', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.userkey?
      return die "UserProvisioning::update expected (String userkey, [Object body, String fields, callback])"
    uri = "https://www.googleapis.com/admin/directory/v1/users/#{args.userkey}"
    uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    opts = { method: 'put', uri: uri, json: (args.body or true) }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  delete: (userkey, cb) =>
    arglist = sanitize arguments, UserProvisioning.delete, [String, Function]
    args = _.object ['userkey', 'cb'], arglist
    die = utils.die_fn args.cb
    return die "UserProvisioning::delete expected (String userkey, [callback])" if not args.userkey?
    uri = "https://www.googleapis.com/admin/directory/v1/users/#{args.userkey}"
    opts = { method: 'delete', uri: uri, json: true }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  # documentation at https://developers.google.com/admin-sdk/directory/v1/reference/users/list
  # and https://developers.google.com/admin-sdk/directory/v1/reference/users/get
  get: (userkey, cb) =>
    # when requesting partial responses with the 'fields' param, you must request the nextPageToken field to enable pagination
    arglist = sanitize arguments, UserProvisioning.get, [String, Function]
    args = _.object ['userkey', 'cb'], arglist
    die = utils.die_fn args.cb
    return die "UserProvisioning::get requires (String userkey, [callback])" if not args.userkey?
    uri = "https://www.googleapis.com/admin/directory/v1/users/#{args.userkey}"
    opts = { json: true, uri: uri }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  list: (params, cb) =>
    if params.fields? and not (_.str.include params.fields, 'nextPageToken')
      params.fields = 'nextPageToken,' + params.fields
    arglist = sanitize arguments, UserProvisioning.list, [Object, Function]
    args = _.object ['params', 'cb'], arglist
    die = utils.die_fn args.cb
    return die "UserProvisioning::list requires (Object params, [callback])" if not args.params?
    uri = "https://www.googleapis.com/admin/directory/v1/users"
    uri += "?#{qs.stringify args.params}" if args.params
    opts = { json: true, uri: uri }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

module.exports = UserProvisioning
