assert = require 'assert'
async  = require 'async'
_      = require 'underscore'
google_apis = require "#{__dirname}/../"
nock   = require 'nock'
util = require 'util'

# There are 3 large test suites in this file:
# describe 'UserProvisioning'
# describe 'OrgUnitProvisioning'
# describe 'GroupProvisioning'

before ->
  nock.disableNetConnect()

beforeEach ->
  nock.cleanAll()

describe 'Retry', ->
  before ->
    @retry_count = 5
    @up = new google_apis.UserProvisioning
      token:
        access: 'fake access token'
    @up.retry_options = {minTimeout: 100, maxTimeout: 200, retries: @retry_count, randomize: true}

  # The following 2 test verifies that @up.get is indeed retrying for @retry_count times.
  # Including the initial request, there are retry_count + 1 total requests.
  it "retries for `retry_count` times but nocked for `(retry_count + 1)` times", (done) ->
    # Nock out all requests with failure
    nock('https://www.googleapis.com:443').get('/admin/directory/v1/users/1234567890')
    .times(@retry_count + 1).reply(500, 'FAIL')

    @up.get '1234567890', (err, data) ->
      assert.equal err, 'FAIL'
      done()

  it 'retries for retry_count times and nocked for retry_count times', (done) ->
    # Nock out all but last request with failure, so that on the (retry_count + 1)th request,
    # it attempts to make a real http request.
    nock('https://www.googleapis.com:443').get('/admin/directory/v1/users/1234567890')
    .times(@retry_count).reply(500, 'FAIL')

    @up.get '1234567890', (err, data) ->
      assert.equal err.name, 'NetConnectNotAllowedError'
      assert.equal err.message, 'Nock: Not allow net connect for "www.googleapis.com:443"'
      done()

describe 'oauth2_request', ->
  it 'does not deadlock with request_refresh_token if no refresh token', (done) ->
    gsdk = new google_apis.AdminSDK
      token:
        refresh: 'sometoken'
        access: 'someaccess'
      client:
        id: 'someid'
        secret: 'somesecret'

    refresh_nock = nock('https://accounts.google.com:443')
    .filteringRequestBody(() -> return '*')
    .post('/o/oauth2/token', '*')
    .reply(400, 'no refresh from google')

    request_nock = nock('https://www.googleapis.com:443').get('/admin/directory/v1/users/1234')
    .reply(401, 'go request token refresh')

    opts =
      json: true
      uri: "https://www.googleapis.com/admin/directory/v1/users/1234"
    gsdk.oauth2_request opts, (err, dontcare) ->
      refresh_nock.done()
      request_nock.done()
      assert.equal err, 'no refresh from google'
      done()

  it 'does not deadlock with request_refresh_token if genuinely invalid credentials', (done) ->
    gsdk = new google_apis.AdminSDK
      token:
        refresh: 'sometoken'
        access: 'someaccess'
      client:
        id: 'someid'
        secret: 'somesecret'

    refresh_nock = nock('https://accounts.google.com:443')
    .filteringRequestBody(() -> return '*')
    .post('/o/oauth2/token', '*')
    .reply(200, 'okay, here you go')

    request_nock = nock('https://www.googleapis.com:443')
    .get('/admin/directory/v1/users/1234').reply(401, 'go request token refresh')
    .get('/admin/directory/v1/users/1234').reply(401, 'nope, genuinely invalid credentials')

    opts =
      json: true
      uri: "https://www.googleapis.com/admin/directory/v1/users/1234"
    gsdk.oauth2_request opts, (err, resp, body) ->
      refresh_nock.done()
      request_nock.done()
      assert.equal resp.statusCode, 401
      assert.equal body, 'nope, genuinely invalid credentials'
      done()

describe 'UserProvisioning', ()->
  before ->
    @up = new google_apis.UserProvisioning
      token:
        access: 'fake access token'
    @up.retry_options = {minTimeout: 100, maxTimeout: 200, retries: 2, randomize: true}

  it 'requires domain, client_id, client_secret upon construction', (done) ->
    assert.throws () ->
      new google_apis.UserProvisioning()
    , Error
    done()

  it 'returns an error when an argument of wrong type is given', (done) ->
    async.waterfall [
      (cb_wf) =>
        @up.get 12345, (err, data) ->
          assert.equal err.toString(), 'Error: UserProvisioning::get requires (String userkey, [callback])'
          cb_wf()
      (cb_wf) =>
        @up.insert 12345, (err, data) ->
          assert.equal err.toString(), "Error: UserProvisioning::insert expected (Object body, [callback])"
          cb_wf()
      (cb_wf) =>
        @up.list 12345, (err, data) ->
          assert.equal err.toString(), "Error: UserProvisioning::list requires (Object params, [callback])"
          cb_wf()
      (cb_wf) =>
        @up.patch 12345, (err, data) ->
          assert.equal err.toString(), "Error: UserProvisioning::patch expected (String userkey, [Object body, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @up.delete 12345, (err, data) ->
          assert.equal err.toString(), "Error: UserProvisioning::delete expected (String userkey, [callback])"
          cb_wf()
    ], done

  ## GET ##
  it 'can get user by id', (done) ->
    body =
      kind: 'admin#directory#user'
      id: '1234567890'
      primaryEmail: 'george@domain.org'
      name: { givenName: 'George', familyName: 'Washington', fullName: 'George Washington' }
      isAdmin: false
      isDelegatedAdmin: false
      lastLoginTime: '1970-01-01T00:00:00.000Z'
      creationTime: '2013-02-20T21:29:18.000Z'
      agreedToTerms: true
      suspended: false
      changePasswordAtNextLogin: false
      ipWhitelisted: false
      emails: [{address: "george@domain.org", primary: true}]
      customerId: 'fake_customer_id'
      orgUnitPath: '/'
      isMailboxSetup: true
      includeInGlobalAddressList: true
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/users/1234567890')
    .reply(200, body)
    @up.get '1234567890', (err, data) ->
      assert.ifError err
      assert.deepEqual data, body
      done()

  it '404s when making get with bad userkey', (done) ->
    body =
      error:
        errors: [{ domain: "global", reason: "notFound", message: "Resource Not Found: userKey" }]
        code: 404
      message: "Resource Not Found: userKey"
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/users/12345')
    .reply(404, body)
    @up.get '12345', (err, data) ->
      assert.deepEqual err, body
      done()


  ## LIST ##
  it 'gets partial response for field argument', (done) ->
    body =
      users: [
        { name: { givenName: "George", familyName: "Washington", fullName: "George Washington" } }
        { name: { givenName: "Lhamo", familyName: "Dondrub", fullName: "Lhamo Dondrub" } }
      ]
      nextPageToken: "next_page"
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/users?domain=domain.org&maxResults=2&fields=users%2Fname%2C%20nextPageToken')
    .reply(200, body)
    @up.list {domain: 'domain.org', maxResults: 2, fields: 'users/name, nextPageToken'}, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'gets users that match a query', (done) ->
    user =
      kind: 'admin#directory#user'
      id: '987654321'
      primaryEmail: 'betsyross@domain.org'
      name: { givenName: 'Betsy', familyName: 'Ross', fullName: 'Betsy Ross' }
      isAdmin: false
      isDelegatedAdmin: false
      lastLoginTime: '1970-01-01T00:00:00.000Z'
      creationTime: '2013-06-25T17:01:23.000Z'
      agreedToTerms: true
      suspended: false
      changePasswordAtNextLogin: false
      ipWhitelisted: false
      emails: [ { address: 'betsyross@domain.org', primary: true } ]
      customerId: 'fake_customer_id'
      orgUnitPath: '/'
      isMailboxSetup: true
      includeInGlobalAddressList: true
    body =
      kind: 'admin#directory#users'
      users: [user]
      nextPageToken: 'next_page'
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/users?domain=domain.org&maxResults=1&query=email%3Abetsy*')
    .reply(200, body)
    @up.list {domain: 'domain.org', maxResults: 1, query: 'email:betsy*'}, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'gets paging info even when not explicitly requested', (done) ->
    body =
      users: [
        { name: { givenName: "George", familyName: "Washington", fullName: "George Washington" } }
        { name: { givenName: "Lhamo", familyName: "Dondrub", fullName: "Lhamo Dondrub" } }
      ]
      nextPageToken: "next_page"
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/users?domain=domain.org&maxResults=2&fields=nextPageToken%2Cusers%2Fname')
    .reply(200, body)
    @up.list {domain: 'domain.org', maxResults: 2, fields: 'users/name'}, (err, data) ->
      assert.deepEqual data, body
      done()

  ## INSERT ##
  it 'creates a user', (done) ->
    post_body =
      name: {familyName: "Gandhi", givenName: "Mahatma"}
      password: "supersecurepassword12345"
      primaryEmail: "mgandhi@domain.org"
    resp_body =
      kind: "admin#directory#user"
      id: "1234567890"
      primaryEmail: "mgandhi@domain.org"
      name: { givenName: "Mahatma", familyName: "Gandhi" }
      isAdmin: false
      isDelegatedAdmin: false
      customerId: "fake_customer_id"
      orgUnitPath: "/"
      isMailboxSetup: false
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/users', post_body)
    .reply(200, resp_body)
    @up.insert post_body, (err, data) ->
      assert.deepEqual data, resp_body
      done()

  ## INSERT, and FAIL ##
  it 'sends a "Domain User Limit" when their domain has its max number of users', (done) ->
    # Lets pretend the domain is already at its user limit when we try to create this user
    post_body =
      name: {familyName: "Gandhi", givenName: "Mahatma"}
      password: "supersecurepassword12345"
      primaryEmail: "mgandhi@domain.org"
    error =
      error:
        errors: [ { domain: 'global', reason: 'DomainUserLimitExceeded', message: 'Domain user limit exceeded.' } ]
        code: 412
        message: 'Domain user limit exceeded.'
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/users', post_body)
    .reply(412, error)
    @up.insert post_body, (err, data) ->
      assert.deepEqual error, err
      done()

  it 'creates a user and returns a partial response', (done) ->
    post_body =
      name: {familyName: "Gandhi", givenName: "Mahatma"}
      password: "supersecurepassword12345"
      primaryEmail: "mgandhi@domain.org"
    resp_body =
      id: "1234567890"
      primaryEmail: "mgandhi@domain.org"
      name: { givenName: "Mahatma", familyName: "Gandhi" }
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/users', post_body)
    .reply(200, resp_body)
    @up.insert post_body, 'name,primaryEmail,id', (err, data) ->
      assert.deepEqual data, resp_body
      done()

  it 'returns an error when trying to create a user without a required field', (done) ->
    post_body =
      name: {familyName: "Gandhi", givenName: "Mahatma"}
      password: "supersecurepassword12345"
    @up.insert post_body, (err, data) ->
      assert.equal(err.toString(), "Error: UserProvisioning::insert requires 'primaryEmail'")
      done()

  ## PATCH ##
  it 'updates a user', (done) ->
    req_body = {name: {familyName: 'Thatcher', givenName: 'Margaret'}}
    resp_body =
      kind: "admin#directory#user"
      id: "1234567890"
      primaryEmail: "mthatcher@domain.org"
      name: { givenName: "Margaret", familyName: "Thatcher" }
      isAdmin: false
      isDelegatedAdmin: false
      lastLoginTime: "1970-01-01T00:00:00.000Z"
      creationTime: "2013-06-25T19:41:26.000Z"
      agreedToTerms: true
      suspended: false
      changePasswordAtNextLogin: false
      ipWhitelisted: false
      emails: [{ address: "mthatcher@domain.org", primary: true }]
      customerId: "fake_customer_id"
      orgUnitPath: "/"
      isMailboxSetup: true
      includeInGlobalAddressList: true
    nock('https://www.googleapis.com:443').persist().patch('/admin/directory/v1/users/1234567890', req_body)
    .reply(200, resp_body)
    @up.patch '1234567890', req_body, (err, data) ->
      assert.deepEqual resp_body, data
      done()

  it '404s when updating with a bad userkey', (done) ->
    req_body = {}
    body =
      error:
        errors: [{ domain: "global", reason: "notFound", message: "Resource Not Found: userKey" }]
        code: 404
      message: "Resource Not Found: userKey"
    nock('https://www.googleapis.com:443').persist().patch('/admin/directory/v1/users/12345', req_body)
    .reply(404, body)
    @up.patch '12345', req_body, (err, data) ->
      assert.deepEqual err, body
      done()

  it 'can correctly call patch with userkey, body, cb', (done) ->
    body =
      kind: 'admin#directory#user'
      id: '1234567890'
      primaryEmail: 'newemail@domain.org'
      name: {givenName: 'Benjamin', familyName: 'Newlastname', fullName: 'Benjamin Newlastname' }
      isAdmin: false
      isDelegatedAdmin: false
      lastLoginTime: '1970-01-01T00:00:00.000Z'
      creationTime: '2013-06-26T03:39:52.000Z'
      agreedToTerms: true
      suspended: false
      changePasswordAtNextLogin: false
      ipWhitelisted: false
      emails: [ { address: 'newemail@domain.org', type: 'custom', primary: true } ]
      customerId: 'fake_customer_id'
      orgUnitPath: '/'
      isMailboxSetup: true
      includeInGlobalAddressList: true
    patch_body =
      name:
        familyName: 'Newlastname'
      primaryEmail: 'newemail@domain.org'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/users/1234567890', patch_body)
    .reply(200, body)
    @up.patch '1234567890', patch_body, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'can correctly call patch with userkey, fields, cb', (done) ->
    body =
      primaryEmail: 'newemail@domain.org'
      name:
        givenName: 'George'
        familyName: 'Newlastname'
        fullName: 'George Newlastname'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/users/1234567890?fields=name%2CprimaryEmail')
    .reply(200, body)
    @up.patch '1234567890', 'name,primaryEmail', (err, data) ->
      assert.deepEqual data, body
      done()

  ## DELETE ##
  it 'deletes a user', (done) ->
    body = {204: "Operation success"}
    nock('https://www.googleapis.com:443').persist().delete('/admin/directory/v1/users/1234567890')
    .reply(204,  body)
    @up.delete '1234567890', (err, data) ->
      assert.deepEqual data, body
      done()

  it '404s when deleting a user with a bad userkey', (done) ->
    body =
      error:
        errors: [{ domain: "global", reason: "notFound", message: "Resource Not Found: userKey" }]
        code: 404
        message: "Resource Not Found: userKey"
    nock('https://www.googleapis.com:443').persist().delete('/admin/directory/v1/users/12345')
    .reply(404, body)
    @up.delete '12345', (err, data) ->
      assert.deepEqual err, body
      done()


describe 'OrgUnitProvisioning', ()->
  ou_not_found =
    error:
      errors: []
      code: 404,
      message: "Org unit not found"

  beforeEach ->
    @ou = new google_apis.OrgUnitProvisioning
      token:
        access: 'access_token'
    @ou.retry_options = {minTimeout: 100, maxTimeout: 200, retries: 2, randomize: true}

  it 'returns an error when an argument of wrong type is given', (done) ->
    async.waterfall [
      (cb_wf) =>
        @ou.get 12345, (err, data) ->
          assert.equal err.toString(), "Error: OrgUnit::get expected (String customer_id, String org_unit_path, [, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @ou.insert 12345, (err, data) ->
          assert.equal err.toString(), "Error: OrgUnit::insert expected (String customer_id, Object properties[, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @ou.list 12345, (err, data) ->
          assert.equal err.toString(), "Error: OrgUnit::list expected (String customer_id[, Object params, callback])"
          cb_wf()
      (cb_wf) =>
        @ou.patch 12345, (err, data) ->
          assert.equal err.toString(), "Error: OrgUnit::patch expected (String customer_id, String org_unit_path, [Object patch_body, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @ou.delete 12345, (err, data) ->
          assert.equal err.toString(), "Error: OrgUnit::delete expected (String customer_id, String org_unit_path[, callback])"
          cb_wf()
    ], done

  it 'can get an OrgUnit', (done) ->
    body =
      kind: 'admin#directory#orgUnit'
      name: 'RockyRoad'
      description: 'For people who like Rocky Road ice cream'
      orgUnitPath: '/RockyRoad'
      parentOrgUnitPath: '/'
      blockInheritance: false
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/customer/fake_customer_id/orgunits/RockyRoad')
    .reply(200, body)
    @ou.get 'fake_customer_id', 'RockyRoad', (err, data) ->
      assert.deepEqual data, body
      done()

  it 'can get an OrgUnit filtered by fields', (done) ->
    body =
      name: 'RockyRoad'
      description: 'For people who like Rocky Road ice cream'
    nock('https://www.googleapis.com:443').persist()
    .get('/admin/directory/v1/customer/fake_customer_id/orgunits/RockyRoad?fields=name%2Cdescription')
    .reply(200, body)
    @ou.get 'fake_customer_id', 'RockyRoad', 'name,description', (err, data) ->
      assert.deepEqual data, body
      done()

  it 'can list all org units for a customer', (done) ->
    body =
      kind: 'admin#directory#orgUnits',
      organizationUnits: [
          kind: 'admin#directory#orgUnit'
          name: 'RockyRoad'
          description: ''
          orgUnitPath: '/RockyRoad'
          parentOrgUnitPath: '/'
          blockInheritance: false
        ,
          kind: 'admin#directory#orgUnit'
          name: 'Vanilla'
          description: ''
          orgUnitPath: '/Vanilla'
          parentOrgUnitPath: '/'
          blockInheritance: false
        ,
          kind: 'admin#directory#orgUnit'
          name: 'ChocolateChipCookieDough'
          description: ''
          orgUnitPath: '/ChocolateChipCookieDough'
          parentOrgUnitPath: '/'
          blockInheritance: false
      ]
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/customer/fake_customer_id/orgunits')
    .reply(200, body)
    @ou.list 'fake_customer_id', (err, data) ->
      assert.deepEqual data, body
      done()

  it 'can list an org unit by params', (done) ->
    body =
      kind: 'admin#directory#orgUnits',
      organizationUnits: [
        { kind: 'admin#directory#orgUnit', name: 'OrgUnit1', description: '', orgUnitPath: '/ParentOU/OrgUnit1', parentOrgUnitPath: '/ParentOU', blockInheritance: false },
        { kind: 'admin#directory#orgUnit', name: 'OrgUnit2', description: '', orgUnitPath: '/ParentOU/OrgUnit2', parentOrgUnitPath: '/ParentOU', blockInheritance: false }
      ]
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/customer/fake_customer_id/orgunits?orgUnitPath=ParentOU')
    .reply(200, body)
    @ou.list 'fake_customer_id', {orgUnitPath: 'ParentOU'}, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'returns 400 with bad customer_id', (done) ->
    error =
      error:
        errors: [{ domain: "global", reason: "badRequest", message: "Bad Request" }]
        code: 400
        message: "Bad Request"
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/customer/asdfasdf/orgunits')
    .reply(400, error)
    @ou.list 'asdfasdf', (err, data) ->
      assert.deepEqual err, error
      done()

  it 'uses cache for OU lookup', (done) ->
    org_unit = ['Students']
    first_ou =
      kind: 'admin#directory#orgUnit'
      name: 'Students'
      orgUnitPath: '/Students'
      orgUnitId: 'ou_id1'
      parentOrgUnitPath: '/'
    second_ou =
      kind: 'admin#directory#orgUnit'
      name: 'Schoolname'
      orgUnitPath: '/Students/SchoolName'
      orgUnitId: 'ou_id2'
      parentOrgUnitPath: '/Students'
    cache = {}
    cache[first_ou.orgUnitPath] = first_ou
    cache[second_ou.orgUnitPath] = second_ou
    @ou.findOrCreate 'abcdef', org_unit, cache, (err, parent, returned_cache) ->
      # this test is successful if it hits the cache and doesn't trigger nock.disableNetConnect()
      assert.ifError err
      assert.deepEqual returned_cache, cache
      assert.equal parent, '/Students'
      done()

  it 'findOrCreate properly memoizes calls to get and insert', (done) ->
    org_unit = ['TestOU']
    properties =
      name: 'TestOU'
      parentOrgUnitPath: '/'
    body =
      kind: 'admin#directory#orgUnit'
      name: org_unit[0]
      orgUnitPath: "/#{org_unit[0]}"
      orgUnitId: 'ou_id'
      parentOrgUnitPath: '/'

    customer_id = "fake_customer_id"

    nock('https://www.googleapis.com')
      .get("/admin/directory/v1/customer/#{customer_id}/orgunits/#{org_unit[0]}")
      .times(3)
      .reply(404, ou_not_found)

    insert_nock = nock('https://www.googleapis.com:443')
      .post("/admin/directory/v1/customer/#{customer_id}/orgunits", properties)
      .reply(200, body)

    expected_cache = {}
    expected_cache[body.orgUnitPath] = body

    # this test is successful if the nock is hit only once, and doesn't trigger nock.disableNetConnect()
    # on subsequent requests
    async.each [0..100], (i, cb_e) =>
      @ou.findOrCreate customer_id, org_unit, {}, (err, parent, returned_cache) ->
        assert.ifError err
        assert.deepEqual returned_cache, expected_cache
        assert.equal parent, '/TestOU'
        cb_e()
    , done


  ## INSERT ##
  it 'creates an orgunit', (done) ->
    properties =
      name: 'TestOU'
      parentOrgUnitPath: '/'
    body =
      kind: 'admin#directory#orgUnit'
      name: 'TestOU'
      orgUnitPath: '/TestOU'
      orgUnitId: 'ou_id'
      parentOrgUnitPath: '/'
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/customer/fake_customer_id/orgunits', properties)
    .reply(200, body)
    @ou.insert 'fake_customer_id', properties, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'returns an orgunit if it already exists', (done) ->
    properties =
      name: 'TestOUAlreadyExists'
      parentOrgUnitPath: '/'
    body =
      kind: 'admin#directory#orgUnit'
      name: 'TestOUAlreadyExists'
      orgUnitPath: '/TestOUAlreadyExists'
      orgUnitId: 'ou_id_already_exists'
      parentOrgUnitPath: '/'
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/customer/fake_customer_id/orgunits/TestOUAlreadyExists')
    .reply(200, body)
    @ou.findOrCreate 'fake_customer_id', ['TestOUAlreadyExists'], (err, parent, cache) ->
      assert.ifError err
      assert.deepEqual cache, {'/TestOUAlreadyExists': body}
      assert.equal parent, '/TestOUAlreadyExists'
      done()

  it 'creates an orgunit if not found', (done) ->
    properties =
      name: 'TestOUCreate'
      parentOrgUnitPath: '/'
    body =
      kind: 'admin#directory#orgUnit'
      name: 'TestOUCreate'
      orgUnitPath: '/TestOUCreate'
      orgUnitId: 'ou_id'
      parentOrgUnitPath: '/'

    nock('https://www.googleapis.com:443').persist()
      .get('/admin/directory/v1/customer/fake_customer_id/orgunits/TestOUCreate')
      .reply(404, ou_not_found)

    insert_nock = nock('https://www.googleapis.com:443')
      .post('/admin/directory/v1/customer/fake_customer_id/orgunits', properties)
      .reply(200, body)

    @ou.findOrCreate 'fake_customer_id', ['TestOUCreate'], (err, parent, cache) ->
      assert.ifError err
      assert.deepEqual cache, {'/TestOUCreate': body}
      assert.equal parent, '/TestOUCreate'
      insert_nock.done()
      done()

  it 'creates an orgunit with fields args for partial response', (done) ->
    properties =
      name: 'TestOU'
      parentOrgUnitPath: '/'
    fields = 'name, orgUnitPath'
    body =
      name: 'TestOU'
      orgUnitPath: '/TestOU'

    nock('https://www.googleapis.com:443').persist()
      .get('/admin/directory/v1/customer/fake_customer_id/orgunits/TestOU')
      .reply(404, ou_not_found)

    nock('https://www.googleapis.com:443').persist()
      .post('/admin/directory/v1/customer/fake_customer_id/orgunits?fields=name%2C%20orgUnitPath', properties)
      .reply(200, body)

    @ou.insert 'fake_customer_id', properties, fields, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'fails to create an orgunit when invalid customer_id is given', (done) ->
    properties =
      name: 'TestOU'
      parentOrgUnitPath: '/'
    error =
      error:
        errors: [{ domain: "global", reason: "badRequest", message: "Bad Request" }]
        code: 400
        message: "Bad Request"

    nock('https://www.googleapis.com:443').persist()
      .get('/admin/directory/v1/customer/fake_customer_id/orgunits/TestOU')
      .reply(404, ou_not_found)

    nock('https://www.googleapis.com:443').persist()
      .post('/admin/directory/v1/customer/badId/orgunits', properties)
      .reply(400, error)

    @ou.insert 'badId', properties, (err, data) ->
      assert.deepEqual err, error
      done()

  it 'fails to create an orgunit when required properties are not given', (done) ->
    properties =
      name: 'TestOU4'
    error =
      error:
        errors: [ { domain: 'global', reason: 'invalid', message: 'Invalid Parent Orgunit Id' } ]
        code: 400
        message: 'Invalid Parent Orgunit Id'

    nock('https://www.googleapis.com:443').persist()
      .get('/admin/directory/v1/customer/fake_customer_id/orgunits/TestOU')
      .reply(404, ou_not_found)

    nock('https://www.googleapis.com:443').persist()
      .post('/admin/directory/v1/customer/fake_customer_id/orgunits', properties)
      .reply(400, error)

    @ou.insert 'fake_customer_id', properties, (err, data) ->
      assert.deepEqual err, error
      done()

  ## DELETE ##
  it 'deletes an orgunit', (done) ->
    body = { 204: 'Operation success' }
    nock('https://www.googleapis.com:443').persist().delete('/admin/directory/v1/customer/fake_customer_id/orgunits/DeleteThis')
    .reply(204, body)
    @ou.delete 'fake_customer_id', 'DeleteThis', (err, data) ->
      assert.deepEqual data, body
      done()

  it '404s when trying to delete a nonexistant an orgunit', (done) ->
    error =
      error:
        errors: [ { domain: 'global', reason: 'notFound', message: 'Org unit not found' } ]
       code: 404
       message: 'Org unit not found'
    nock('https://www.googleapis.com:443').persist().delete('/admin/directory/v1/customer/fake_customer_id/orgunits/doesnotexist')
    .reply(404, error)
    @ou.delete 'fake_customer_id', 'doesnotexist', (err, data) ->
      assert.deepEqual err, error
      done()

  ## PATCH ##
  it 'updates an OrgUnit', (done) ->
    patch_body = {name: 'UpdatedName'}
    body =
      kind: 'admin#directory#orgUnit'
      name: 'UpdatedName'
      orgUnitPath: '/UpdatedName'
      parentOrgUnitPath: '/'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/customer/fake_customer_id/orgunits/UpdateThisName', patch_body)
    .reply(200, body)
    @ou.patch 'fake_customer_id', 'UpdateThisName', patch_body, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'updates an OrgUnit and returns a partial response', (done) ->
    patch_body = {name: 'UpdatedName'}
    body =
      name: 'UpdatedName'
      orgUnitPath: '/UpdatedName'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/customer/fake_customer_id/orgunits/UpdateThisName?fields=name%2CorgUnitPath', patch_body)
    .reply(200, body)
    @ou.patch 'fake_customer_id', 'UpdateThisName', patch_body, 'name,orgUnitPath', (err, data) ->
      assert.deepEqual data, body
      done()

  it 'can call update with no patch_body', (done) ->
    body = { name: 'UpdateThisName' }
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/customer/fake_customer_id/orgunits/UpdateThisName?fields=name')
    .reply(200, body)
    @ou.patch 'fake_customer_id', 'UpdateThisName', 'name', (err, data) ->
      assert.deepEqual data, body
      done()

  it 'update returns an error when called with an invalid customer_id', (done) ->
    error =
      errors: [ { domain: 'global', reason: 'authError', message: 'Invalid Credentials', locationType: 'header', location: 'Authorization' } ]
      code: 401
      message: 'Invalid Credentials'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/customer/bad_id/orgunits/UpdateThisName?fields=name')
    .reply(401, error)
    @ou.patch 'bad_id', 'UpdateThisName', 'name', (err, data) ->
      assert.deepEqual err, error
      done()

describe 'GroupProvisioning', ()->
  before ->
    @gp = new google_apis.GroupProvisioning
      token:
        access: 'fake_access_token'
    @gp.retry_options = {minTimeout: 100, maxTimeout: 200, retries: 2, randomize: true}

  it 'returns an error when an argument of wrong type is given', (done) ->
    async.waterfall [
      (cb_wf) =>
        @gp.get 12345, (err, data) ->
          assert.equal err.toString(), "Error: GroupProvisioning::get expected (String group_key[, callback])"
          cb_wf()
      (cb_wf) =>
        @gp.insert 12345, (err, data) ->
          assert.equal err.toString(), "Error: GroupProvisioning::insert expected (Object properties[, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @gp.list 12345, (err, data) ->
          assert.equal err.toString(), "Error: GroupProvisioning::list expected (Object params[, callback])"
          cb_wf()
      (cb_wf) =>
        @gp.patch 12345, (err, data) ->
          assert.equal err.toString(), "Error: GroupProvisioning::delete expected (String group_key[, Object body, String fields, callback])"
          cb_wf()
      (cb_wf) =>
        @gp.delete 12345, (err, data) ->
          assert.equal err.toString(), "Error: GroupProvisioning::delete expected (String group_key[, callback])"
          cb_wf()
    ], done

  ## LIST ##
  it 'lists groups for a domain', (done) ->
    body =
      kind: 'admin#directory#groups'
      groups: [{
        id: 'abcd1234'
        email: 'group1@domain.org',
        name: 'Group1',
        description: 'the first group'
      }]
      nextPageToken: 'next_page'
    params =
      domain: 'domain.org'
      maxResults: 1
      fields: 'groups(description,email,id,name),kind,nextPageToken'
    nock('https://www.googleapis.com:443').persist()
    .get('/admin/directory/v1/groups?domain=domain.org&maxResults=1&fields=groups(description%2Cemail%2Cid%2Cname)%2Ckind%2CnextPageToken')
    .reply(200, body)
    @gp.list params, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'returns an error when an invalid param is given', (done) ->
    params =
      domain: 'domain.org'
      maxResults: 1
      unknown_field: true
    @gp.list params, (err, data) ->
      assert.equal err.toString(), "Error: GroupProvisioning::list invalid param 'unknown_field'"
      done()

  it 'returns 404 for a valid parameter that doesn not exist', (done) ->
    params =
      domain: 'badexample.com'
      maxResults: 1
    error =
     errors: [ { domain: 'global', reason: 'notFound', message: 'Resource Not Found: badexample.com' } ]
     code: 404
     message: 'Resource Not Found: badexample.com'
    nock('https://www.googleapis.com:443').persist()
    .get('/admin/directory/v1/groups?domain=badexample.com&maxResults=1')
    .reply(404, error)
    @gp.list params, (err, data) ->
      assert.deepEqual err, error
      done()

  ## GET ##
  it 'can get group by group_key', (done) ->
    body =
      kind: 'admin#directory#group'
      id: 'abcd1234'
      email: 'group1@domain.org'
      name: 'Group1'
      description: 'the first group'
      adminCreated: true
    nock('https://www.googleapis.com:443').persist().get('/admin/directory/v1/groups/abcd1234')
    .reply(200, body)
    @gp.get 'abcd1234', (err, data) ->
      assert.deepEqual data, body
      done()

  it '404s when trying to get a group by invalid group_key', (done) ->
    error =
      error:
        errors: [ { domain: 'global', reason: 'notFound', message: 'Resource Not Found: groupKey' } ]
        code: 404
        message: 'Resource Not Found: groupKey'
    nock('https://www.googleapis.com:443').persist()
    .get('/admin/directory/v1/groups/badkey')
    .reply(404, error)
    @gp.get 'badkey', (err, data) ->
      assert.deepEqual err, error
      done()

  ## INSERT ##
  it 'can insert a group', (done) ->
    fields = 'description,email,id'
    body =
      id: 'abcd1234'
      email: 'newgroup@domain.org'
      description: 'new test group'
    properties =
      email: 'newgroup@domain.org'
      description: 'new test group'
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/groups?fields=description%2Cemail%2Cid', properties)
    .reply(200, body)
    @gp.insert properties, fields, (err, data) ->
      assert.deepEqual data, body
      done()

  it 'returns an error when trying to insert a group without required properties', (done) ->
    error =
      error:
        errors: [ { domain: 'global', reason: 'required', message: 'Missing required field: email' } ]
        code: 400
        message: 'Missing required field: email'
    properties =
      description: 'no email for this group'
    nock('https://www.googleapis.com:443').persist().post('/admin/directory/v1/groups', properties)
    .reply(400, error)
    @gp.insert properties, (err, data) ->
      assert.deepEqual err, error
      done()

  ## DELETE ##
  it 'can delete a group', (done) ->
    nock('https://www.googleapis.com:443').persist() .delete('/admin/directory/v1/groups/abcd1234')
    .reply(204, "")
    @gp.delete 'abcd1234', (err, data) ->
      assert.deepEqual data, { 204: 'Operation success'}
      done()

  it 'delete returns an error when a nonstring group_key is given', (done) ->
    @gp.delete 12345, (err, data) ->
      assert.equal err.toString(), 'Error: GroupProvisioning::delete expected (String group_key[, callback])'
      done()

  it 'returns an error when a nonexistant group_key is given', (done) ->
    error =
      error:
        errors: [ { domain: 'global', reason: 'notFound', message: 'Resource Not Found: groupKey' } ]
        code: 404
        message: 'Resource Not Found: groupKey'
    nock('https://www.googleapis.com:443').persist()
    .delete('/admin/directory/v1/groups/asdf1234asdf')
    .reply(404, error)
    @gp.delete 'asdf1234asdf', (err, data) ->
      assert.deepEqual err, error
      done()

  it 'updates a group', (done) ->
    req_body =
      name: 'Updated group'
      description: 'new description'
    resp_body =
      id: 'abcd1234'
      email: 'group1@domain.org'
      name: 'Updated group'
      description: 'new description'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/groups/abcd1234?fields=id%2Cname%2Cdescription%2Cemail', req_body)
    .reply(200, resp_body)
    @gp.patch 'abcd1234', req_body, 'id,name,description,email', (err, data) ->
      assert.deepEqual data, resp_body
      done()

  it '404s when updating with a bad group_key', (done) ->
    req_body = {name: 'Updated group'}
    error =
      error:
        errors: [ { domain: 'global', reason: 'notFound', message: 'Resource Not Found: groupKey' } ]
        code: 404,
        message: 'Resource Not Found: groupKey'
    nock('https://www.googleapis.com:443').persist()
    .patch('/admin/directory/v1/groups/12345', req_body)
    .reply(404, error)
    @gp.patch '12345', req_body, (err, data) ->
      assert.deepEqual err, error
      done()
