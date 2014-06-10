fs      = require 'fs'
Q       = require 'q'

unsynch      = require './unsynch'
convert      = require '../text-encodings'
BitPaddedInt = require '../bit-padded-int'
{Frame}      = require './frame'

{ValueError, EOFError, NotImplementedError} = require '../errors'
{ID3NoHeaderError, ID3UnsupportedVersionError, ID3JunkFrameError} = require './errors'

class Parser
  constructor: (@tag, @context) -> this

  read: (size) ->
    throw new ValueError("Requested bytes #{size} less than zero") if (size < 0)

    {fd, position, fileSize} = @context

    if (fileSize? && size > fileSize)
      throw new EOFError("Requested #{size} of #{fileSize} #{@filepath}")

    readingFile = Q.nfcall(fs.read, fd, new Buffer(size), 0, size, position)

    readingFile.spread (bytesRead, buff) =>
      throw new EOFError('End of file') if bytesRead isnt size

      @context.position += bytesRead
      return buff

  loadHeader: ->
    @read(10).then (data) =>
      offset = 0
      id3 = (convert data[offset...offset+=3]).from 'latin1'

      @tag.version = {
        major : 2
        minor : data.readUInt8(offset++)
        sub   : data.readUInt8(offset++)
      }

      @tag._flags = data.readUInt8(offset++)

      sizeRepr = (convert data[offset...offset+=4]).from 'latin1'
      @tag.size = BitPaddedInt(sizeRepr) + 10

      unless id3 is 'ID3'
        throw new ID3NoHeaderError("#{@tag.filepath} doesn't start with an ID3 tag")

      unless @tag.version.minor in [2,3,4]
        msg = "#{@tag.filepath} ID3v2.#{@tag.version.minor} not supported"
        throw new ID3UnsupportedVersionError(msg)

      unless @tag.f_extended
        return @tag

      do @loadExtendedHeader

  loadExtendedHeader: ->
    @read(4).then (data) =>
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
        @tag._flags = (@tag._flags ^ 0x40)
        @tag.extSize = 0
        @context.position -= 4
      else if @tag.version.minor >= 4
        # "Where the 'Extended header size' is the size of the whole
        # extended header, stored as a 32 bit synchsafe integer."
        @tag.extSize = BitPaddedInt(extSizeRepr) - 4
      else
        # "Where the 'Extended header size', currently 6 or 10 bytes,
        # excludes itself."
        @tag.extSize = BitPaddedInt(extSizeRepr, 8)

      @tag.extData = new Buffer('')

      return @tag unless @tag.extSize

      @read(@tag.extSize).then (data) =>
        @tag.extData = data
        return @tag

  readV2Frames: ->
    @read(@tag.size - 10).then (buff) =>
      if @tag.version.minor >= 3      then frames = Frame.FRAMES
      else if @tag.version.minor <= 2 then frames = Frame.FRAMES_2_2

      readFrame = @getFrameReader(buff, frames)
      loadingFrames = []
      while (frame = do readFrame)
        loadingFrames.push(frame)

      return Q
        .allSettled(loadingFrames)
        .then (resolved) =>
          frames = []; errors = []
          for promise in resolved
            if promise.state is 'fulfilled'
              frames.push(promise.value)
            else
              errors.push(promise.reason)

          for err in errors
            throw err unless err instanceof ID3JunkFrameError

          for frame in frames
            #TODO: Does not account for the upgrade to 2.4 tags mutagen performs
            if frame instanceof Frame then @tag.add(frame)
            else if frame?            then @tag.unknownFrames.push(frame)

          return @tag

  readV1Frames: ->
    # Move 128 bytes from end of file
    @context.position = (@context.fileSize - 128)

    @read(128).then (buff) =>
      frames = ParseID3v1(buff)

      return null unless frames?

      @tag.version = { major: 1, minor: 1 }
      @tag.add(frame) for name,frame of frames

      return @tag

  determineBPI: (data, frames) ->
    EMPTY="\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

    if (@tag.version.minor < 4)
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

  getFrameReader: (data, frames) ->
    if ((@tag.version.minor < 4) && @tag.f_unsynch)
      try
        data = unsynch.decode(data)
      catch err
        throw err unless err instanceof ValueError

    if (3 <= @tag.version.minor)
      bpi = @determineBPI(data, frames)
      reader = () =>
        while data.length > 0
          # Node versions < 0.10 throw out of bounds error when slicing beyond
          # end of Buffer. If that would happen, default to buffer.length.
          bound = if data.length < 10 then data.length else 10
          header = data[0...bound]
          offset = 0

          try
            name   = (convert header[offset...offset+=4]).from 'latin1'
            size   = header.readUInt32BE(offset); offset+=4
            flags  = header.readUInt16BE(offset)
          catch err
            return false  # not enough header

          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          size      = bpi(size)
          frameEnd  = 10+size
          frameEnd  = data.length-1 if (frameEnd > data.length)
          framedata = data[10...frameEnd]
          data      = data[frameEnd..]

          continue if (size == 0) # drop empty frames

          frame = frames[name]
          ##TODO: Temporary conditional workaround while we're
          ## defining specs
          # unless tag is undefined
          unless frame is undefined or typeof frame is 'string'
            return @tag.loadFramedata(frame, flags, framedata)
              .fail (err) ->
                if err instanceof NotImplementedError
                  return Buffer.concat([header, framedata])

                throw err
          else
            return Buffer.concat([header, framedata]) if Frame.isValidFrameId(name)

    else if (2 <= @tag.version.minor)
      reader = () =>
        while data.length > 0
          bound = if data.length < 6 then data.length else 6
          header = data[0...bound]
          offset = 0

          try
            name = (convert header[offset...offset+= 3]).from 'latin1'

            size = header[offset...offset+= 3]
            size = Buffer.concat([new Buffer('00','hex'), size])
            size = size.readUInt32BE(0)
          catch err
            return false  # not enough header

          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          frameEnd  = 6+size
          frameEnd  = data.length-1 if (frameEnd > data.length)
          framedata = data[6...frameEnd]
          data      = data[frameEnd..]

          continue if (size == 0) # drop empty frames

          frame = frames[name]
          ##TODO: Temporary conditional workaround while we're
          ## defining specs
          # unless tag is undefined
          unless frame is undefined or typeof frame is 'string'
            return @tag.loadFramedata(frame, 0, framedata)
              .fail (err) ->
                if err instanceof NotImplementedError
                  return Buffer.concat([header, framedata])

                throw err
          else
            return Buffer.concat([header, framedata]) if Frame.isValidFrameId(name)

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

module.exports = Parser
