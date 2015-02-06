GoogleAPIAdminSDK = require "#{__dirname}/google_api_admin_sdk"
qs        = require 'qs'
_         = require 'underscore'
utils     = require "#{__dirname}/utils"
sanitize  = require 'sanitize-arguments'
{Query}   = require "#{__dirname}/query.coffee"

class GroupProvisioning extends GoogleAPIAdminSDK
  list: (params, cb) ->
    arglist = sanitize arguments, GroupProvisioning.list, [Object, Function]
    args = _.object ['params', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.params?
      return die "GroupProvisioning::list expected (Object params[, callback])"
    valid_params = ['customer', 'domain', 'maxResults', 'pageToken', 'userKey', 'fields']
    for param, val of args.params
      return die "GroupProvisioning::list invalid param '#{param}'" if not _(valid_params).contains(param)
    uri = "https://www.googleapis.com/admin/directory/v1/groups"
    opts = { json: true, qs: args.params, uri: uri}
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  get: (group_key, cb) ->
    arglist = sanitize arguments, GroupProvisioning.get, [String, Function]
    args = _.object ['group_key', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.group_key?
      return die 'GroupProvisioning::get expected (String group_key[, callback])'
    uri = "https://www.googleapis.com/admin/directory/v1/groups/#{args.group_key}"
    opts = { json: true, uri: uri}
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  insert: (properties, fields, cb) ->
    arglist = sanitize arguments, GroupProvisioning.insert, [Object, String, Function]
    args = _.object ['properties', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.properties?
      return die 'GroupProvisioning::insert expected (Object properties[, String fields, callback])'
    uri = "https://www.googleapis.com/admin/directory/v1/groups"
    opts = { method: 'post', json: args.properties, uri: uri }
    opts.qs = {fields: args.fields} if args.fields?
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  delete: (group_key, cb) ->
    arglist = sanitize arguments, GroupProvisioning.delete, [String, Function]
    args = _.object ['group_key', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.group_key?
      return die 'GroupProvisioning::delete expected (String group_key[, callback])'
    uri = "https://www.googleapis.com/admin/directory/v1/groups/#{args.group_key}"
    opts = { method: 'delete', json: true, uri: uri }
    opts.qs = {fields: args.fields} if args.fields?
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  patch: (group_key, body, fields, cb) ->
    arglist = sanitize arguments, GroupProvisioning.patch, [String, Object, String, Function]
    args = _.object ['group_key', 'body', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.group_key?
      return die 'GroupProvisioning::delete expected (String group_key[, Object body, String fields, callback])'
    return die "group_key cannot be an email address" if utils.is_email args.group_key
    uri = "https://www.googleapis.com/admin/directory/v1/groups/#{args.group_key}"
    uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    opts = { method: 'patch', uri: uri, json: (args.body or true) }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

module.exports = GroupProvisioning
