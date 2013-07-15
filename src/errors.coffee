class BaseError extends Error
  constructor: (msg) ->
    Error.captureStackTrace this, @constructor
    @name = @constructor.name
    @message = msg
    super

class EOFError extends BaseError
class NotImplementedError extends BaseError
class ValueError extends BaseError
class UnicodeDecodeError extends ValueError

module.exports = {BaseError, EOFError, NotImplementedError, ValueError, UnicodeDecodeError}
