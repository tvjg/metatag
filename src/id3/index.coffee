fs      = require 'fs'
Q       = require 'q'

Parser = require './parser'

{EOFError} = require '../errors'
{ID3NoHeaderError, ID3UnsupportedVersionError} = require './errors'

# https://github.com/kriskowal/q#long-stack-traces
Q.longStackSupport = true

class ID3
  constructor: (filepath) ->
    # The following properties are defined to be non-enumerable and
    # non-configurable in keeping with mutagen convention which uses Python
    # name mangling to hide most of these properties. It instead favors
    # exposing the ID3 frames as iterable key-value pairs via its DictProxy
    # base class.

    Object.defineProperties this, {
      filepath:
        writable: true
        value: null

      # raw frame data of any unknown frames found
      unknownFrames:
        writable: false
        value: []

      # the total size of the ID3 tag, including the header
      size:
        writable: true
        value: 0

      # ID3v2 spec actually refers to the minor number as the major version and
      # the subminor number as the revision. Mutagen uses tuples to handle this
      # in a terminology free way, but we don't have that option, so just use
      # neutral terms instead of ID3 spec terms.
      version:
        writable: true
        value: { major: 2, minor: 4, sub: 0 },

      extSize:
        writable: true
        value: null

      extData:
        writable: true
        value: null

      _flags:
        writable: true
        value: 0
    }

    @load(arguments...) if arguments.length > 0

  Object.defineProperties @prototype, {
    f_unsynch:
      get: -> ((@_flags & 0x80) != 0)

    f_extended:
      get: -> ((@_flags & 0x40) != 0)

    f_experimental:
      get: -> ((@_flags & 0x20) != 0)

    f_footer:
      get: -> ((@_flags & 0x10) != 0)

    PEDANTIC:
      writable: false
      value: true
  }

  load: (@filepath, callback) ->
    context = { fd: null, fileSize: null, position: 0 }
    parser  = new Parser(this, context)

    openingFile = Q.nfcall(fs.open, filepath, 'r')
    sizingFile  = Q.nfcall(fs.stat, filepath)

    closeFile = =>
      closing = if context.fd then Q.nfcall(fs.close, context.fd) else true

      context = null
      parser = null

      #FIXME: do @update_to_v24 if translate

      return closing

    return Q
      .all([openingFile, sizingFile])

      .spread (fd, stat) =>
        context.fd = fd
        context.fileSize = stat.size

        do parser.loadHeader

      .then ->
        do parser.readV2Frames

      .fail (err) =>
        endOfFile          = err instanceof EOFError
        noHeader           = err instanceof ID3NoHeaderError
        unsupportedVersion = err instanceof ID3UnsupportedVersionError

        switch
          when endOfFile
            @size = 0
            msg = "#{@filepath}: too small (#{context.fileSize} bytes)"
            throw new ID3NoHeaderError(msg)

          when noHeader or unsupportedVersion
            @size = 0
            throw err if context.fileSize < 128

            do parser.readV1Frames

          else throw err

      .fin(closeFile)
      .nodeify(callback)

  add: (frame) ->
    # if len(type(tag).__name__) == 3: tag = type(tag).__base__(tag)
    this[frame.HashKey] = frame

  loadFramedata: (tag, flags, data) -> tag.fromData(tag, this, flags, data)

module.exports = ID3
