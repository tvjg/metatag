fs      = require 'fs'
_       = require 'underscore'
sprintf = require("sprintf-js").sprintf
convert = require './text-encodings'
unsynch = require './unsynch'

BitPaddedInt = require './BitPaddedInt'
Frame = require './Frame'

BaseError = require('./errors.js').BaseError
EOFError = require('./errors.js').EOFError
class ID3NoHeaderError extends BaseError
class ID3UnsupportedVersionError extends BaseError

class ID3
  constructor: (filepath) ->
    # The following properties are defined to be non-enumerable and
    # non-configurable in keeping with mutagen convention which uses Python
    # name mangling to hide most of these properties. It instead favors
    # exposing the ID3 frames as iterable key-value pairs via its DictProxy
    # base class.

    Object.defineProperty(this, 'filepath', { 
      writable: true
      value: filepath || null,
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

    # Don't care for exposing these _properties, but yet to find a way to
    # encapsulate them without resorting to obtuse tricks to emulate private
    # properties.

    Object.defineProperty(this, '_fd', { writable: true, value: null });
    Object.defineProperty(this, '_fileSize', { writable: true, value: null });
    
    # Read cursor is needed since fs doesn't expose seek method.
    Object.defineProperty(this, '_readBytes', { writable: true, value: 0 });
   
    Object.defineProperty(this, '_extSize', { writable: true, value: null });
    Object.defineProperty(this, '_extData', { writable: true, value: null });

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

    @load(filepath) if filepath?

  fullRead: (size) ->
    throw new Error "Requested bytes #{size} less than zero" if (size < 0)
    throw new EOFError "Requested #{size} of #{@_fileSize} #{@filepath}" if (@_fileSize? && size > @_fileSize)

    buff = new Buffer size
    bytesRead = fs.readSync @_fd, buff, 0, size, @_readBytes

    throw new EOFError 'End of file' if bytesRead isnt size

    @_readBytes += bytesRead
    return buff

  load: (@filepath) ->
    @_fd  = fs.openSync filepath, 'r'
    @_fileSize = fs.statSync(filepath).size

    try
      headerLoaded = false
      
      try
        do @loadHeader
        headerLoaded = true
      catch err
        if err instanceof EOFError
          @size = 0
          throw new ID3NoHeaderError "#{@filepath}: too small (#{@_fileSize} bytes)"
        else if err instanceof ID3NoHeaderError or err instanceof ID3UnsupportedVersionError
          @size = 0

          throw err if @_fileSize < 128
          
          # Attempt to parse as ID3v1
          # Skip 128 bytes from EOF
          @_readBytes = (@_fileSize - 128)
          frames = ParseID3v1(@fullRead(128))

          throw err unless frames?

          @version = { major: 1, minor: 1 }
          @add frame for name,frame of frames
        
      finally
        if headerLoaded
          if @version.minor >= 3      then frames = Frame.FRAMES
          else if @version.minor <= 2 then frames = Frame.FRAMES_2_2
        
          data      = @fullRead (@size - 10)
          readFrame = @getFrameReader data,frames
          frame     = false
          while (frame = do readFrame) isnt false
            #TODO: Does not account for the upgrade to 2.3/2.4 tags that
            # mutagen uses
            if frame instanceof Frame then @add frame
            else if frame?            then @unknownFrames.push frame

    finally
      fs.closeSync @_fd
      @_fd  = null
      @_fileSize = null
      # if translate:
      #   self.update_to_v24()

  add: (frame) ->
    # if len(type(tag).__name__) == 3: tag = type(tag).__base__(tag)
    this[frame.HashKey] = frame

  loadHeader: () ->
    data = @fullRead 10
    
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

    throw new ID3NoHeaderError "#{@filepath} doesn't start with an ID3 tag" unless id3 is 'ID3'
    throw new ID3UnsupportedVersionError "#{@filepath} ID3v2.#{@version.minor} not supported" unless @version.minor in [2,3,4]

    if @f_extended
      data = @fullRead 4
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
        @_extSize = 0
        @_readBytes -= 4
      else if @version.minor >= 4
        # "Where the 'Extended header size' is the size of the whole
        # extended header, stored as a 32 bit synchsafe integer."
        @_extSize = BitPaddedInt(extSizeRepr) - 4
      else
        # "Where the 'Extended header size', currently 6 or 10 bytes,
        # excludes itself."
        @_extSize = BitPaddedInt(extSizeRepr, 8)

      @_extData = ''
      if @_extSize
        data = @fullRead @_extSize
        @_extData = data.toString('hex')

  getFrameReader: (data, frames) ->
    if ((@version.minor < 4) && @f_unsynch)
      try
        data = unsynch.decode(data)
      catch err #TODO: Mutagen is only passing ValueError here

    if (3 <= @version.minor)
      bpi = @determineBPI data,frames
      reader = () => 
        loop
          try
            header = data[0...10]
            offset = 0
            
            name   = (convert header[offset...offset+=4]).from 'latin1'
            size   = header.readUInt32BE(offset); offset+=4
            flags  = header.readUInt16BE(offset)
          catch err
            console.log @filepath
            console.log err.stack, '\n'
            # not enough header
            return false 

          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          size      = bpi(size)
          framedata = data[10...10+size]
          data      = data[10+size..]
          
          break unless (size == 0) # drop empty frames

        tag = frames[name]
        ##TODO: Temporary conditional workaround while we're
        ## defining specs
        # if tag is undefined
        if tag is undefined or typeof tag is 'string'
          if Frame.isValidFrameId(name) then return header + framedata
        else
          try
            return @loadFramedata(tag, flags, framedata)
          catch err
            console.log @filepath
            console.log err.stack, '\n'
            ## except NotImplementedError: yield header + framedata
            ## except ID3JunkFrameError: pass
    
    else if (2 <= @version.minor)
      reader = () =>
        loop
          try
            header = data[0...6]
            offset = 0 
            
            name   = (convert header[offset...offset+=3]).from 'latin1'
            size   = header[offset...offset+=3]
          catch err
            console.log @filepath
            console.log err.stack, '\n'
            # not enough header
            return false

          ## size, = struct.unpack('>L', '\x00'+size)
          size = Buffer.concat([new Buffer('00','hex'), size])
          size = size.readUInt32BE(0)
          if ((name.replace(/[\x00]+$/g, '')) == '') then return false
          
          framedata = data[6...6+size]
          data      = data[6+size..]

          break unless (size == 0) # drop empty frames
        
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
            console.log @filepath
            console.log err.stack, '\n'
            ## except NotImplementedError: yield header + framedata
            ## except ID3JunkFrameError: pass
  
  loadFramedata: (tag, flags, data) -> tag.fromData(tag,this,flags,data)

  determineBPI: (data, frames) ->
    #TODO: Does this logic equate?
    # EMPTY="\x00" * 10
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

  #if genre != 255: frames["TCON"] = TCON(encoding=0, text=str(genre))
  
  return frames
