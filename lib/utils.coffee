_ = require 'underscore'

module.exports =
  die_fn: (cb) ->
    (err_txt) ->
      return cb new Error err_txt if _(cb).isFunction()
      throw Error err_txt # only option if no cb

  is_email: (str) ->
    return false if not str?
    return str.match /^([\w.-]+)@([\w.-]+)\.([a-zA-Z.]{2,6})$/i
