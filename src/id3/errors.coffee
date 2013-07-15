{ValueError, NotImplementedError} = require '../errors'

class ID3NoHeaderError extends ValueError
class ID3BadUnsynchData extends ValueError

class ID3UnsupportedVersionError extends NotImplementedError
class ID3EncyptionUnsupportedError extends NotImplementedError

class ID3JunkFrameError extends ValueError

module.exports = { 
  ID3NoHeaderError
  ID3BadUnsynchData
  ID3UnsupportedVersionError
  ID3EncyptionUnsupportedError
  ID3JunkFrameError
}
