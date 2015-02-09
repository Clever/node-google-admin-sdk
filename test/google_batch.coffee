assert = require 'assert'
async  = require 'async'
_      = require 'underscore'
google_apis = require "#{__dirname}/../"
nock   = require 'nock'
util = require 'util'

before ->
  nock.disableNetConnect()

describe 'Batch Requests', ->
  before ->
    @options =
      token:
        access: 'fake_access_token'

    @up = new google_apis.UserProvisioning @options

    # filter out random boundary strings and set them to a known value so messages can be diff'd
    @boundary_filter = (res) ->
      res.replace(/\n\-\-[0-9a-zA-Z=]+\n/g, '\n--===============1234567890123456789==\n')
        .replace(/\n\-\-[0-9a-zA-Z=]+\-\-/g, '\n--===============1234567890123456789==--')

    @user_defaults =
      id: "1234"
      primaryEmail: "ben.franklin@example.com"
      name: { givenName: "Ben", familyName: "Franklin", fullName: "Ben Franklin" }
      lastLoginTime: "2013-09-27T18:56:04.000Z"
      creationTime: "2013-09-24T22:06:21.000Z"
      emails: [{ address: "ben.franklin@example.com", primary: true }]
      kind: "admin#directory#user"
      isAdmin: false
      isDelegatedAdmin: false
      agreedToTerms: true
      suspended: false
      changePasswordAtNextLogin: false
      ipWhitelisted: false
      customerId: "fake_customer_id"
      orgUnitPath: "/"
      isMailboxSetup: true
      includeInGlobalAddressList: true

    @request_helper = (ids) ->
      request = "\n--===============1234567890123456789=="
      for id in ids
        request += "\nContent-Type: application/http\n\n" +
        "GET /admin/directory/v1/users/#{id} HTTP/1.1\n" +
        "--===============1234567890123456789=="
      request + "--"

  it 'requires options upon construction', ->
    assert.throws ->
      new google_apis.Batch()
    , Error

  it 'can perform multiple get requests', (done) ->
    #nock.recorder.rec()
    test_data = [
      user_id: '1234'
      expected_data: _.defaults { isDelegatedAdmin: true }, @user_defaults
    ,
      user_id: '5678'
      expected_data: _.defaults
        id: "5678"
        primaryEmail: "admin@example.com"
        name: { givenName: "The", familyName: "Admin", fullName: "The Admin" }
        isAdmin: true
        lastLoginTime: "2013-09-27T18:57:15.000Z"
        creationTime: "2013-09-24T21:41:29.000Z"
        emails: [{ address: "admin@example.com", primary: true }]
        orgUnitPath: "/Google Administrators"
        , @user_defaults
    ,
      user_id: '9012'
      expected_data: _.defaults
        id: "9012"
        primaryEmail: "matchmealso@ga4edu.org"
        name: { givenName: "User2", familyName: "Match", fullName: "User2 Match" }
        lastLoginTime: "1970-01-01T00:00:00.000Z"
        creationTime: "2013-08-02T23:31:07.000Z"
        emails: [{ address: "matchmealso@ga4edu.org", primary: true }]
        orgUnitPath: "/NotAdmins"
        , @user_defaults
    ]

    expected_request = @request_helper ['1234', '5678', '9012']

    expected_reply = "--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    _.each test_data, (test) =>
      expected_reply += "Content-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
      expected_reply += JSON.stringify test.expected_data
      expected_reply += "\r\n--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    expected_reply += "--"

    nock('https://www.googleapis.com:443')
      .get('/oauth2/v1/tokeninfo?access_token=fake_access_token')
      .reply(200, "OK")
      .filteringRequestBody(@boundary_filter)
      .post('/batch', expected_request)
      .reply 200, expected_reply,
        { 'content-type': 'multipart/mixed; boundary=batch_7av0UPcSyII=_ABKN5zORmiQ=' }

    queries = _(test_data).map (test) => @up.get test.user_id

    batch = new google_apis.Batch @options
    batch.go queries, (err, results) ->
      assert.ifError err
      _.each (_.zip results, test_data), ([result, test]) ->
        assert.equal result.statusCode, 200
        assert.deepEqual test.expected_data, result.body
      done()

  it 'can send requests with content', (done) ->
    get_resp_body = _.defaults { isDelegatedAdmin: true }, @user_defaults

    patch_req_body = {name: {familyName: 'Jefferson', givenName: 'Thomas'}}
    patch_resp_body = _.defaults
      kind: "admin#directory#user"
      id: "55555"
      primaryEmail: "thomas.jefferson@example.com"
      name: { givenName: "Thomas", familyName: "Jefferson" }
      lastLoginTime: "1970-01-01T00:00:00.000Z"
      creationTime: "2013-06-25T19:41:26.000Z"
      emails: [{ address: "thomas.jefferson@example.com", primary: true }]
      , @user_defaults

    expected_request =
      "\n--===============1234567890123456789==\n" +
      "Content-Type: application/http\n\n" +
      "GET /admin/directory/v1/users/1234 HTTP/1.1\n" +
      "--===============1234567890123456789==\n" +
      "Content-Type: application/http\n\n" +
      "PATCH /admin/directory/v1/users/55555 HTTP/1.1\n" +
      "Content-Type: application/json\n" +
      "content-length: #{(JSON.stringify patch_req_body).length}\n\n" +
      "#{JSON.stringify patch_req_body}\n" +
      "--===============1234567890123456789==--"

    expected_reply = "--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    expected_reply += "Content-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
    expected_reply += JSON.stringify get_resp_body
    expected_reply += "\r\n--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    expected_reply += "Content-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
    expected_reply += JSON.stringify patch_resp_body
    expected_reply += "\r\n--batch_7av0UPcSyII=_ABKN5zORmiQ=--"

    nock('https://www.googleapis.com:443')
      .get('/oauth2/v1/tokeninfo?access_token=fake_access_token')
      .reply(200, "OK")
      .filteringRequestBody(@boundary_filter)
      .post('/batch', expected_request)
      .reply 200, expected_reply,
        { 'content-type': 'multipart/mixed; boundary=batch_7av0UPcSyII=_ABKN5zORmiQ=' }

    queries = [(@up.get '1234'), (@up.patch '55555', patch_req_body)]

    batch = new google_apis.Batch @options
    batch.go queries, (err, results) ->
      assert.ifError err
      _.each (_.zip results, [get_resp_body, patch_resp_body]), ([result, test]) ->
        assert.equal result.statusCode, 200
        assert.deepEqual test, result.body
      done()

  it 'will throw a batch error correctly', (done) ->
    nock('https://www.googleapis.com:443')
      .get('/oauth2/v1/tokeninfo?access_token=fake_access_token')
      .reply(200, "OK")
      .post('/batch')
      .reply 404, "We accidently rimraf"

    batch = new google_apis.Batch @options

    batch.go [(@up.get 'bad_id'), (@up.get 'bad_id_2')], (err, results) ->
      assert err?
      done()

  it 'will retry slowly if rate-limited', (done) ->
    #nock.recorder.rec()
    test_data = [
      user_id: '1234'
      expected_data: _.defaults { isDelegatedAdmin: true }, @user_defaults
    ]

    expected_request = @request_helper ['1234']

    expected_reply = "--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    _.each test_data, (test) =>
      expected_reply += "Content-Type: application/http\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
      expected_reply += JSON.stringify test.expected_data
      expected_reply += "\r\n--batch_7av0UPcSyII=_ABKN5zORmiQ=\r\n"
    expected_reply += "--"

    nock('https://www.googleapis.com:443')
      .get('/oauth2/v1/tokeninfo?access_token=fake_access_token')
      .reply(200, "OK")
      .filteringRequestBody(@boundary_filter)
      .post('/batch', expected_request)
      .reply(503, 'Enhance your calm')
      .post('/batch', expected_request)
      .reply(503, 'Enhance your calm')
      .post('/batch', expected_request)
      .reply 200, expected_reply,
        { 'content-type': 'multipart/mixed; boundary=batch_7av0UPcSyII=_ABKN5zORmiQ=' }

    queries = _(test_data).map (test) => @up.get test.user_id

    batch = new google_apis.Batch @options
    batch.go queries, (err, results) ->
      assert.ifError err
      _.each (_.zip results, test_data), ([result, test]) ->
        assert.equal result.statusCode, 200
        assert.deepEqual test.expected_data, result.body
      done()
