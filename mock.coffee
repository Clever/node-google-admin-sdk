require 'coffee-errors'
_ = require 'underscore'
sinon = require 'sinon'
admin_sdk = require "#{__dirname}"
{Readable} = require 'stream'
sanitize = require 'sanitize-arguments'
async = require 'async'

module.exports =
  get_google_sandbox: (data, id_num = 100000000) ->
    sandbox = sinon.sandbox.create()

    admin_sdk.data = data
    admin_sdk.sandbox = sandbox
    admin_sdk.restore = -> sandbox.restore()

    sandbox.stub admin_sdk.OrgUnitProvisioning.prototype, 'insert', (customer_id, properties, cb) =>
      parent = properties.parentOrgUnitPath
      name = properties.name
      full_path = if parent is '/' then "/#{name}" else "#{parent}/#{name}"
      if full_path in admin_sdk.data.orgunits
        err =
          error:
            errors: [ { domain: 'global', reason: 'invalid', message: 'Invalid Ou Id' } ]
            code: 400
            message: 'Invalid Ou Id'
        return cb err, null
      else
        admin_sdk.data.orgunits.push full_path
        response =
          kind: "admin#directory#orgUnit"
          name: properties.name
          orgUnitPath: full_path
          parentOrgUnitPath: properties.parentOrgUnitPath
        return cb null, response

    sandbox.stub admin_sdk.UserProvisioning.prototype, 'insert', (body, fields, cb) =>
      if _(fields).isFunction()
        cb = fields

      q = exec: (cb_exec) =>
        if _(admin_sdk.data.users).any((user) -> user.primaryEmail.toLowerCase() is body.primaryEmail.toLowerCase())
          return cb_exec error: { code: 409, message: 'Entity already exists.' }
        generated_properties =
          hashFunction: 'SHA-1'
          kind: "admin#directory#user"
          id: "" + id_num++
          isAdmin: false
          isDelegatedAdmin: false
          isMailboxSetup: false
        ga_user = _.extend(body, generated_properties)
        admin_sdk.data.users[generated_properties.id] = ga_user
        cb_exec null, 200, _.omit(ga_user, 'password')
      return q unless cb?
      q.exec cb

    sandbox.stub admin_sdk.UserProvisioning.prototype, 'patch', (userkey, body, fields, cb) =>
      arglist = sanitize arguments, admin_sdk.UserProvisioning.patch, [String, Object, String, Function]
      args = _.object ['userkey', 'body', 'fields', 'cb'], arglist
      admin_sdk.data.users[args.userkey][key] = value for key, value of args.body
      ###
      A PATCH to the Directory API to update a field whose value is an array will overwrite the array *except*
      in the case that the new value is an empty array. In this case, the value is unchanged. It's not clear
      if this undocumented behavior is intentional.
      ###
      for key, value of args.body
        admin_sdk.data.users[args.userkey][key] = value unless _.isEqual value, []
      if args.fields?
        args.cb null, _(admin_sdk.data.users[args.userkey]).pick fields
      else
        args.cb null, admin_sdk.data.users[args.userkey]

    sandbox.stub admin_sdk.UserProvisioning.prototype, 'get', (userkey, cb) =>
      q = exec: (cb_exec) =>
        return cb_exec null, admin_sdk.data.users[userkey] if admin_sdk.data.users[userkey]? # user_id
        for user_id, user of admin_sdk.data.users
          if user.primaryEmail is userkey
            return cb_exec null, user
        err =
         error:
          errors: [domain: "global", reason: "notFound", message: "Resource Not Found: userKey"]
          code: 404
          message: "Resource Not Found: userKey"
        cb_exec err
      return q unless cb?
      q.exec cb

    sandbox.stub admin_sdk.Batch.prototype, 'go', (queries, cb) =>
      console.log "Doing batch of #{queries.length}"
      async.map queries, ((query, cb_m) ->
        query.exec (err, status_code, result) ->
          cb_m err, { statusCode: status_code, body: result }
      ), cb

    # assumes the only function to make Queries is user/list
    sandbox.stub admin_sdk.GoogleQuery.Query.prototype, 'stream', () ->
      return new SimpleStream admin_sdk.data.users

    class SimpleStream extends Readable
      constructor: (@_data) ->
        @data = _(@_data).values()
        super { objectMode: true }
        @i = 0
      _read: () =>
        @push @data[@i++] # will push(null) when i >= data.length

    admin_sdk
