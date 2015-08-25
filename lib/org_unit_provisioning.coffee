GoogleAPIAdminSDK = require "#{__dirname}/google_api_admin_sdk"
_         = require 'underscore'
utils     = require "#{__dirname}/utils"
{Query}   = require "#{__dirname}/query.coffee"
qs        = require 'qs'
sanitize  = require 'sanitize-arguments'
async     = require 'async'
retry     = require 'retry'

class OrgUnit extends GoogleAPIAdminSDK
  # TODO: possibly make customer_id an option of OrgUnit
  # customer_id, org_unit_path required
  # if no patch_body is provided, update behaves like get
  # fields returns only selected properties of an OrgUnit object
  patch: (customer_id, org_unit_path, patch_body, fields, cb) =>
    arglist = sanitize arguments, OrgUnit.patch, [String, String, Object, String, Function]
    args = _.object ['customer_id', 'org_unit_path', 'patch_body', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.customer_id? or not args.org_unit_path?
      return die "OrgUnit::patch expected (String customer_id, String org_unit_path, [Object patch_body, String fields, callback])"
    uri = "https://www.googleapis.com/admin/directory/v1/customer/#{args.customer_id}/orgunits/#{args.org_unit_path}"
    uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    opts = { method: 'patch', uri: uri, json: (args.patch_body or true) }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  insert: (customer_id, properties, fields, cb) =>
    arglist = sanitize arguments, OrgUnit.insert, [String, Object, String, Function]
    args = _.object ['customer_id', 'properties', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.customer_id? or not args.properties?
      return die "OrgUnit::insert expected (String customer_id, Object properties[, String fields, callback])"
    uri = "https://www.googleapis.com/admin/directory/v1/customer/#{args.customer_id}/orgunits"
    uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    opts = { method: 'post', uri: uri, json: properties }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb


  delete: (customer_id, org_unit_path, cb) =>
    arglist = sanitize arguments, OrgUnit.delete, [String, String, Function]
    args = _.object ['customer_id', 'org_unit_path', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.customer_id? or not args.org_unit_path?
      return die "OrgUnit::delete expected (String customer_id, String org_unit_path[, callback])"
    uri = "https://www.googleapis.com/admin/directory/v1/customer/#{args.customer_id}/orgunits/#{args.org_unit_path}"
    opts = { method: 'delete', uri: uri, json: true }
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  list: (customer_id, params, cb) =>
    arglist = sanitize arguments, OrgUnit.list, [String, Object, Function]
    args = _.object ['customer_id', 'params', 'cb'], arglist
    die = utils.die_fn args.cb
    return die "OrgUnit::list expected (String customer_id[, Object params, callback])" if not args.customer_id?
    opts = { json: true }
    opts.uri = "https://www.googleapis.com/admin/directory/v1/customer/#{args.customer_id}/orgunits"
    opts.uri += "?#{qs.stringify args.params}" if args.params?
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  get: (customer_id, org_unit_path, fields, cb) =>
    arglist = sanitize arguments, OrgUnit.get, [String, String, String, Function]
    args = _.object ['customer_id', 'org_unit_path', 'fields', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.customer_id? or not args.org_unit_path?
      return die "OrgUnit::get expected (String customer_id, String org_unit_path, [, String fields, callback])"
    opts = { json: true }
    opts.uri = "https://www.googleapis.com/admin/directory/v1/customer/#{args.customer_id}/orgunits/#{args.org_unit_path}"
    opts.uri += "?#{qs.stringify {fields: args.fields}}" if args.fields?
    q = new Query @, opts
    return q unless args.cb?
    q.exec args.cb

  # takes customer_id, array of orgunit levels eg. ['CleverStudents', 'Schoolname', ...], and optional cache, and callback
  # returns callback w/ args orgunit string '/Students/Schoolname' and cache of orgunits created '/', '/Students', '/Students/Schoolname'
  findOrCreate: (customer_id, org_unit, cache, cb) =>
    if _(cache).isFunction()
      cb = cache
      cache = {}
    arglist = sanitize arguments, OrgUnit.findOrCreate, [String, Array, Function]
    args = _.object ['customer_id', 'org_unit', 'cb'], arglist
    die = utils.die_fn args.cb
    if not args.customer_id? or not args.org_unit?
      return die "OrgUnit::findOrCreate expected (String customer_id, Array org_unit, [callback])"
    parent = '/'

    # for each level in the OU, find that OU or create it and store the response in the cache
    async.eachSeries args.org_unit, (level, cb_es) =>
      full_path = if parent is '/' then "/#{level}" else "#{parent}/#{level}"
      if cache[full_path]?
        parent = full_path
        return cb_es()

      @atomic_get_or_create full_path, args.customer_id, level, parent, @, (err, results) ->
        return cb_es err if err?
        cache[full_path] = results.body
        parent = results.parent
        cb_es err, results.body
    , (err) ->
      return die err if err?
      cb null, parent, cache

  # use async.memoize for two reasons:
  # 1. Ensure that the actual find-or-create action is executed at most once.
  #      This avoids a race condition in which the consumer of this library
  #      calls findOrCreate with multiple concurrency
  # 2. Increases performance
  # We don't access the cache of the memoized function - we use our own for readability
  atomic_get_or_create: async.memoize (full_path, customer_id, level, parent, that, cb) =>
    console.log "Call memoize fn", full_path
    async.waterfall [
      (cb_wf) =>
        # Make a request to find this OU first. Only make an insert request if the OU doesn't
        # already exist.
        that.get customer_id, full_path[1..], (err, body) ->
          if err?
            if err.error?.code is 404 and err.error?.message is "Org unit not found"
              # Not found; pass through to create the orgunit
              return cb_wf null, null
            else
              # A valid error was returned. Return the error and skip the insert.
              return cb_wf err

          # If no error, we found the orgunit. Cache it and skip insert because it already exists.
          # cache[full_path] = body
          parent = full_path
          return cb_wf null, body
      (body, cb_wf) =>
        # No need to insert because the org unit was found
        return cb_wf null, body if body?

        # Google interface: `name` requires no slash, parentOrgUnitPath requires a slash
        that.insert customer_id, { name: level, parentOrgUnitPath: parent }, (err, body) =>
          return cb_es "Unable to create org unit #{full_path}: #{JSON.stringify err}" if err?
          # cache[full_path] = body
          parent = full_path
          cb_wf null, { body, parent }
    ], cb


module.exports = OrgUnit
