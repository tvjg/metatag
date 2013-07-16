fs      = require 'fs'
Q       = require 'q'
sprintf = require("sprintf-js").sprintf

convert      = require '../text-encodings'
unsynch      = require './unsynch'
BitPaddedInt = require '../BitPaddedInt'
Frame        = require './frame'

{ValueError, EOFError, NotImplementedError} = require '../errors'
{ID3NoHeaderError, ID3UnsupportedVersionError, ID3JunkFrameError} = require './errors'

# https://github.com/kriskowal/q#long-stack-traces
Q.longStackSupport = true

class ID3
  constructor: (filepath) ->
    # The following properties are defined to be non-enumerable and
    # non-configurable in keeping with mutagen convention which uses Python
    # name mangling to hide most of these properties. It instead favors
    # exposing the ID3 frames as iterable key-value pairs via its DictProxy
    # base class.

    Object.defineProperty(this, 'PEDANTIC', {
      writable: false
      value: true,
    });

    Object.defineProperty(this, 'filepath', {
      writable: true
      value: null,
    });

    # the total size of the ID3 tag, including the header
    Object.defineProperty(this, 'size', {
      writable: true
      value: 0,
    });

    # raw frame data of any unknown frames found
    Object.defineProperty(this, 'unknownFrames', {
      writable: false
      value: []
    });

    # ID3v2 spec actually refers to the minor number as the major version and
    # the subminor number as the revision. Mutagen uses tuples to handle this
    # in a terminology free way, but we don't have that option, so just use
    # neutral terms instead of ID3 spec terms.
    Object.defineProperty(this, 'version', {
      writable: true
      value: { major: 2, minor: 4, sub: 0 },
    });

    Object.defineProperty(this, 'extSize', { writable: true, value: null });
    Object.defineProperty(this, 'extData', { writable: true, value: null });

    Object.defineProperty(this, '_flags', { writable: true, value: 0 });

    Object.defineProperty(this, 'f_unsynch', {
      get: () -> ((@_flags & 0x80) != 0)
    });
    Object.defineProperty(this, 'f_extended', {
      get: () -> ((@_flags & 0x40) != 0)
    });
    Object.defineProperty(this, 'f_experimental', {
      get: () -> ((@_flags & 0x20) != 0)
    });
    Object.defineProperty(this, 'f_footer', {
      get: () -> ((@_flags & 0x10) != 0)
    });

    @load(arguments...) if arguments.length > 0

  fullRead: (context, size) ->
    throw new ValueError("Requested bytes #{size} less than zero") if (size < 0)

    if (context.fileSize? && size > context.fileSize)
      throw new EOFError("Requested #{size} of #{context.fileSize} #{@filepath}")

    readingFile = Q.nfcall(fs.read, context.fd, new Buffer(size), 0, size, context.position)

    return readingFile.spread (bytesRead, buff) =>
      throw new EOFError('End of file') if bytesRead isnt size

      context.position += bytesRead
      return buff

  load: (@filepath, callback) ->

    # TODO: While moving in the right direction, this retains an unpleasant
    # smell. Too many practically anonymous methods hidden in the scopes of
    # load and loadHeader primarily for the purpose of sharing the file context
    # info.  It creates a block of methods to read and hold in mind before
    # getting to the meat of load: the now streamlined chain of steps
    # implementing the strategy for reading file metadata.
    #
    # Likely, a new Parser class should be created with a context property. The
    # bulk of these methods that concern themselves with the actual business of
    # file reads could be moved there. This keeps this class clear of
    # distraction and forms it into a proper wrapper for presenting ID3 data to
    # the library user. This should also help further shift the unit tests away
    # from priming ugly _privateMethod properties and functions with values to
    # in order to test isolated functionality like fullRead and loadHeader.

    openingFile = Q.nfcall(fs.open, filepath, 'r')
    sizingFile  = Q.nfcall(fs.stat, filepath)

    context = { fd: null, fileSize: null, position: 0 }

    parseV2Frames = (buff) =>
      if @version.minor >= 3      then frames = Frame.FRAMES
      else if @version.minor <= 2 then frames = Frame.FRAMES_2_2

      readFrame = @getFrameReader buff,frames
      frame     = false
      while (frame = do readFrame) isnt false
        #TODO: Does not account for the upgrade to 2.3/2.4 tags that
        # mutagen uses
        if frame instanceof Frame then @add frame
        else if frame?            then @unknownFrames.push frame

      return this

    parseV1Frames = (buff) =>
      frames = ParseID3v1(buff)

      throw err unless frames?

      @version = { major: 1, minor: 1 }
      @add frame for name,frame of frames

      return this

    closeFile = () =>
      closing = if context.fd then Q.nfcall(fs.close, context.fd) else true

      context = null

      #FIXME: do @update_to_v24 if translate

      return closing

    return Q
      .all([openingFile, sizingFile])
      .spread (fd, stat) =>
        context.fd = fd
        context.fileSize = stat.size

        return @loadHeader(context)

      .then(() => @fullRead(context, @size - 10))
      .then(parseV2Frames)
      .fail (err) =>
        switch
          when err instanceof EOFError
            @size = 0
            throw new ID3NoHeaderError "#{@filepath}: too small (#{context.fileSize} bytes)"

          when err instanceof ID3NoHeaderError, err instanceof ID3UnsupportedVersionError
            @size = 0
            throw err if context.fileSize < 128

            context.position = (context.fileSize - 128)
            return @fullRead(context, 128).then(parseV1Frames)

          else throw err

      .fin(closeFile)
      .nodeify(callback)

  add: (frame) ->
    # if len(type(tag).__name__) == 3: tag = type(tag).__base__(tag)
    this[frame.HashKey] = frame

  loadHeader: (context) ->
    parseExtendedHeader = (data) =>
      extSizeRepr = (convert data).from 'latin1'

      if Frame.FRAMES[extSizeRepr]
        # Some tagger sets the extended header flag but
        # doesn't write an extended header; in this case, the
        # ID3 data follows immediately. Since no extended
        # header is going to be long enough to actually match
        # a frame, and if it's *not* a frame we're going to be
        # completely lost anyway, this seems to be the most
        # correct check.
        # http://code.google.com/p/quodlibet/issues/detail?id=126
        @_flags = (@_flags ^ 0x40)
        @extSize = 0
        context.position -= 4
      else if @version.minor >= 4
        # "Where the 'Extended header size' is the size of the whole
        # extended header, stored as a 32 bit synchsafe integer."
        @extSize = BitPaddedInt(extSizeRepr) - 4
      else
        # "Where the 'Extended header size', currently 6 or 10 bytes,
        # excludes itself."
        @extSize = BitPaddedInt(extSizeRepr, 8)

      @extData = new Buffer('')

      return this unless @extSize

      return @fullRead(context, @extSize).then( (@extData) => this )

    return @fullRead(context, 10)
      .then (data) =>
        offset = 0
        id3 = (convert data[offset...offset+=3]).from 'latin1'

        @version = {
          major : 2
          minor : data.readUInt8(offset++)
          sub   : data.readUInt8(offset++)
        }

        @_flags = data.readUInt8(offset++)

        sizeRepr = (convert data[offset...offset+=4]).from 'latin1'
        @size = BitPaddedInt(sizeRepr) + 10;

        throw new ID3NoHeaderError("#{@filepath} doesn't start with an ID3 tag") unless id3 is 'ID3'
        throw new ID3UnsupportedVersionError("#{@filepath} ID3v2.#{@version.minor} not supported") unless @version.minor in [2,3,4]

        return this unless @f_extended

        return @fullRead(context, 4).then(parseExtendedHeader)

  getFrameReader: (data, frames) ->
    if ((@version.minor < 4) && @f_unsynch)
      try
        data = unsynch.decode(data)
      catch err
        throw err unless err instanceof ValueError

    if (3 <= @version.minor)
      bpi = @determineBPI data,frames
      reader = () =>
        while data.length > 0
          header = data[0...10]
          offset = 0

          try
            name   = (convert header[offset...offset+=4]).from 'latin1'
            size   = header.readUInt32BE(offset); offset+=4
            flags  = header.readUInt16BE(offset)
          catch err
            return false  # not enough header

          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          size      = bpi(size)
          framedata = data[10...10+size]
          data      = data[10+size..]

          continue if (size == 0) # drop empty frames

          tag = frames[name]
          ##TODO: Temporary conditional workaround while we're
          ## defining specs
          # if tag is undefined
          if tag is undefined or typeof tag is 'string'
            if Frame.isValidFrameId(name) then return Buffer.concat(header, framedata)
          else
            try
              return @loadFramedata(tag, flags, framedata)
            catch err
              if err instanceof NotImplementedError
                return Buffer.concat(header, framedata)

              continue if err instanceof ID3JunkFrameError

              throw err

    else if (2 <= @version.minor)
      reader = () =>
        while data.length > 0
          header = data[0...6]
          offset = 0

          try
            name   = (convert header[offset...offset+=3]).from 'latin1'
            size   = header[offset...offset+=3]
          catch err
            return false  # not enough header

          ## size, = struct.unpack('>L', '\x00'+size)
          size = Buffer.concat([new Buffer('00','hex'), size])
          size = size.readUInt32BE(0)
          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          framedata = data[6...6+size]
          data      = data[6+size..]

          continue if (size == 0) # drop empty frames

          tag = frames[name]
          ##TODO: Temporary conditional workaround while we're
          ## defining specs
          # if tag is undefined
          if tag is undefined or typeof tag is 'string'
            if Frame.isValidFrameId(name) then return header + framedata
          else
            try
              return @loadFramedata(tag, 0, framedata)
            catch err
              if err instanceof NotImplementedError
                return Buffer.concat(header, framedata)

              continue if err instanceof ID3JunkFrameError

              throw err

  loadFramedata: (tag, flags, data) -> tag.fromData(tag,this,flags,data)

  determineBPI: (data, frames) ->
    EMPTY="\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

    if (@version.minor < 4)
      return (i) -> parseInt(i, 10)

    ## have to special case whether to use bitpaddedints here
    ## spec says to use them, but iTunes has it wrong
    #
    ## count number of tags found as BitPaddedInt and how far past
    o = 0
    asbpi = 0
    while o < (data.length - 10)
      part = data[o...o + 10]
      if part is EMPTY
        bpioff = -((data.length - o) % 10)
        break
      name   = (convert part[0...4]).from('latin1')
      size   = part.readUInt32BE(4)
      flags  = part.readUInt16BE(8)
      size = BitPaddedInt(size)
      o += 10 + size
      if frames[name]? then asbpi++

      if not o < (data.length - 10)
        bpioff = o - data.length

    ## count number of tags found as int and how far past
    o = 0
    asint = 0
    while o < (data.length - 10)
      part = data[o...o + 10]
      if part is EMPTY
        intoff = -((data.length - o) % 10)
        break
      name   = (convert part[0...4]).from 'latin1'
      size   = part.readUInt32BE(4)
      flags  = part.readUInt16BE(8)
      o += 10 + size
      if frames[name]? then asint++

      if not o < (data.length - 10)
        intoff = o - data.length

    ## if more tags as int, or equal and bpi is past and int is not
    if (asint > asbpi) or ((asint is asbpi) and ((bpioff >= 1) and (intoff <= 1)))
      return (i) -> parseInt(i, 10)

    (i) -> BitPaddedInt(i)

module.exports = ID3

# ID3v1.1 support.
ParseID3v1 = (buffer) ->
  # Parse an ID3v1 tag, returning a list of ID3v2.4 frames.

  # In theory at least, all ID3v1 frames are ISO8859-1
  hexString = buffer.toString('hex')
  hexString = hexString[hexString.indexOf('544147')...]
  if hexString is -1
    return null

  tagByteLength = Buffer.byteLength(hexString,'hex')
  if 128 < tagByteLength or tagByteLength < 124
    return null

  buffer = new Buffer(hexString, 'hex')

  ## Issue #69 - Previous versions of Mutagen, when encountering
  ## out-of-spec TDRC and TYER frames of less than four characters,
  ## wrote only the characters available - e.g. "1" or "" - into the
  ## year field. To parse those, reduce the size of the year field.
  ## Amazingly, "0s" works as a struct format string.
  #unpack_fmt = "3s30s30s30s%ds29sBB" % (tagByteLength - 124)

  try
    #tag, title, artist, album, year, comment, track, genre = unpack(unpack_fmt, string)
    offset = 0
    tag     = (convert buffer[offset...offset+= 3]).from 'latin1'
    title   = (convert buffer[offset...offset+= 30]).from 'latin1'
    artist  = (convert buffer[offset...offset+= 30]).from 'latin1'
    album   = (convert buffer[offset...offset+= 30]).from 'latin1'
    year    = (convert buffer[offset...offset+= (tagByteLength - 124)]).from 'latin1'
    comment = (convert buffer[offset...offset+= 29]).from 'latin1'
    track = buffer.readUInt8(offset++)
    genre = buffer.readUInt8(offset++)
  catch err
    return null

  if tag isnt 'TAG'
    return null

  fix = (string) ->
    string.split('\u0000')[0].trim()

  [ title, artist, album, year, comment ] = (fix str for str in [title, artist, album, year, comment])

  frames = {}
  frames["TIT2"] = new Frame.FRAMES.TIT2({encoding:0, text:title}) if title
  frames["TPE1"] = new Frame.FRAMES.TPE1({encoding:0, text:[artist]}) if artist
  frames["TALB"] = new Frame.FRAMES.TALB({encoding:0, text:album}) if album
  frames["TDRC"] = new Frame.FRAMES.TDRC({encoding:0, text:year}) if year

  if comment
    frames["COMM"] = new Frame.FRAMES.COMM({
      encoding:0,
      lang:"eng",
      desc:"ID3v1 Comment",
      text:comment
    })

  # Don't read a track number if it looks like the comment was
  # padded with spaces instead of nulls (thanks, WinAmp).
  if track and (track != 32 or hexString[-6..-5] == '00')
    frames["TRCK"] = new Frame.FRAMES.TRCK({encoding:0, text:track.toString()})

  if genre != 255
    frames["TCON"] = new Frame.FRAMES.TCON({encoding:0, text:genre.toString()})

  return frames
