class BaseError extends Error
  constructor: (msg) ->
    Error.captureStackTrace this, @constructor
    @name = @constructor.name
    @message = msg
    super

class EOFError extends BaseError

module.exports = {BaseError, EOFError}
