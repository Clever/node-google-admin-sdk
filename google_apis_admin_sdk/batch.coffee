async = require 'async'
GoogleAPIAdminSDK = require "#{__dirname}/google_api_admin_sdk"
url = require 'url'
quest       = require 'quest'
MailParser  = (require 'mailparser').MailParser
http_parser = require 'http-string-parser'
_ = require 'underscore'
retry = require 'retry'

class Batch
  constructor: (google_opts) ->
    @queries = []
    @google_api = new GoogleAPIAdminSDK google_opts

  go: (queries, cb) ->
    return cb null, [] if queries.length is 0

    async.waterfall [
      (cb_wf) =>
        @google_api.tokeninfo (err, result) =>
          if err?
            @google_api.request_refresh_token cb_wf
          else
            cb_wf null, null
      (dontcare, cb_wf) =>
        boundary = '===============7330845974216740156=='
        request_body = _.map(queries, (query) ->
          pathname = (url.parse query._opts.uri).pathname
          method = query._opts.method?.toUpperCase() ? "GET"
          body = "\n--#{boundary}\nContent-Type: application/http\n\n#{method} #{pathname} HTTP/1.1"
          if (query._opts.json? and query._opts.json isnt true)
            content_body = JSON.stringify query._opts.json
            body += "\nContent-Type: application/json"
            body += "\ncontent-length: #{content_body.length}"
            body += "\n\n#{content_body}"
          body
        ).join('') + "\n--#{boundary}--"

        options =
          method: 'post'
          uri: "https://www.googleapis.com/batch"
          body: request_body
          headers:
            Authorization: "Bearer #{@google_api.options.token.access}"
            'content-type': "multipart/mixed; boundary=\"#{boundary}\""

        operation = retry.operation { maxTimeout: 3 * 60 * 1000, retries: 15 }
        operation.attempt ->
          quest options, (err, res, body) ->
            return null if res.statusCode is 503 and operation.retry(new Error(""))
            cb_wf err, res, body
      (res, body, cb_wf) =>
        unless res.statusCode is 200
          return cb_wf new Error "Batch API responded with code #{res.statusCode}"

        # It is unlikely the above retry logic will work since it would mean the entire batch
        # request failed to go through.
        # What is more likely to happen is that individual requests within the batch could fail.
        # And so what is returned to the cb of Batch.go is an array of responses.
        mail_parser = new MailParser()
        mail_parser.end "Content-type: #{res.headers['content-type']}\r\n\r\n#{body}"
        mail_parser.on 'end', (mail) ->
          cb_wf null, _(mail.attachments).map (result) ->
            parsed_response = http_parser.parseResponse result.content.toString()
            parsed_response.body = JSON.parse parsed_response.body if parsed_response.body
            parsed_response.statusCode = +parsed_response.statusCode
            parsed_response
    ], cb

module.exports = Batch
