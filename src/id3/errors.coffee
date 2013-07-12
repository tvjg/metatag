{BaseError} = require '../errors'

class ID3NoHeaderError extends BaseError
class ID3UnsupportedVersionError extends BaseError

module.exports = { 
  ID3NoHeaderError
  ID3UnsupportedVersionError
}
