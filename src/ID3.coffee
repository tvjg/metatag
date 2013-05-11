fs      = require 'fs'
_       = require 'underscore'
sprintf = require("sprintf-js").sprintf
Iconv = require('iconv').Iconv

BitPaddedInt = require('./BitPaddedInt.js')

BaseError = require('./errors.js').BaseError
EOFError = require('./errors.js').EOFError
class ID3NoHeaderError extends BaseError
class ID3UnsupportedVersionError extends BaseError

latin1ToUTF8 = new Iconv('ISO-8859-1','UTF-8')
utf16 = new Iconv('UTF-16','UTF-8')
utf16be = new Iconv('UTF-16BE','UTF-8')

convertToString = (iconv) ->
  (buffer) -> (iconv.convert buffer).toString()

fromLatin1ToString = convertToString latin1ToUTF8 
fromUTF16ToString = convertToString utf16 
fromUTF16BEToString = convertToString utf16be 
fromUTF8ToString = (buff) -> buff.toString()

class ID3
  constructor: (filepath) ->
    @__readbytes   = 0
    @unknownFrames = []

    @load(filepath) if filepath?

  fullRead: (size) ->
    throw new Error "Requested bytes #{size} less than zero" if (size < 0)
    throw new EOFError "Requested #{size} of #{@__filesize} #{@filepath}" if (size > @__filesize)

    buff = new Buffer size
    bytesRead = fs.readSync @__fileobj, buff, 0, size, @__readbytes

    throw new EOFError 'End of file' if bytesRead isnt size

    @__readbytes += bytesRead
    return buff

  load: (@filepath) ->
    @__fileobj  = fs.openSync filepath, 'r'
    @__filesize = fs.statSync(filepath).size

    try
      headerLoaded = false
      
      try
        do @loadHeader
        headerLoaded = true
      catch err
        if err instanceof EOFError
          @size = 0
          throw new ID3NoHeaderError "#{@filepath}: too small (#{@__filesize} bytes)"
        else if err instanceof ID3NoHeaderError or err instanceof ID3UnsupportedVersionError
          @size = 0

          if @__filesize >= 128
            #TODO: Don't really like this manipulation.
            @__readbytes = (@__filesize - 128)
            frames = ParseID3v1(@fullRead(128))
            if frames
              @version.majorRev = 1
              @version.minorRev = 1
              @add frame for name,frame of frames
            else 
              throw err
          else
            throw err
        
      finally
        if headerLoaded
          if @version.majorRev >= 3      then frames = FRAMES
          else if @version.majorRev <= 2 then frames = FRAMES_2_2
        
          data      = @fullRead (@size - 10)
          readFrame = @getFrameReader data,frames
          frame     = false
          while (frame = do readFrame) isnt false
            #TODO: Does not account for the upgrade to 2.3/2.4 tags that
            # mutagen uses
            if frame instanceof Frame then @add frame
            else if frame?            then @unknownFrames.push frame

    finally
      fs.closeSync @__fileobj
      @__fileobj  = null
      @__filesize = null
      # if translate:
      #   self.update_to_v24()

  add: (frame) ->
    # if len(type(tag).__name__) == 3: tag = type(tag).__base__(tag)
    this[frame.HashKey] = frame

  loadHeader: () ->
    data = @fullRead 10
    
    offset = 0
    id3 = fromLatin1ToString data[offset...offset+=3]

    @version = {
      majorRev : data.readUInt8(offset++)
      minorRev : data.readUInt8(offset++)
    }
  
    flags = data.readUInt8(offset++)
    @f_unsynch      = ((flags & 0x80) != 0) 
    @f_extended     = ((flags & 0x40) != 0)
    @f_experimental = ((flags & 0x20) != 0)
    @f_footer       = ((flags & 0x10) != 0)
   
    sizeRepr = fromLatin1ToString data[offset...offset+=4]
    @size = BitPaddedInt(sizeRepr) + 10;

    throw new ID3NoHeaderError "#{@filepath} doesn't start with an ID3 tag" unless id3 is 'ID3'
    throw new ID3UnsupportedVersionError "#{@filepath} ID3v2.#{@version.majorRev} not supported" unless @version.majorRev in [2,3,4]

    if @f_extended
      data = @fullRead 4
      extSizeRepr = fromLatin1ToString data
    
      if _.include(FRAMES, extSizeRepr) 
        # Some tagger sets the extended header flag but
        # doesn't write an extended header; in this case, the
        # ID3 data follows immediately. Since no extended
        # header is going to be long enough to actually match
        # a frame, and if it's *not* a frame we're going to be
        # completely lost anyway, this seems to be the most
        # correct check.
        # http://code.google.com/p/quodlibet/issues/detail?id=126
        @f_extended = false
        @__extsize = 0
        @__readbytes -= 4
      else if @version.majorRev >= 4
        # "Where the 'Extended header size' is the size of the whole
        # extended header, stored as a 32 bit synchsafe integer."
        @__extsize = BitPaddedInt(extSizeRepr) - 4
      else
        # "Where the 'Extended header size', currently 6 or 10 bytes,
        # excludes itself."
        @__extsize = BitPaddedInt(extSizeRepr, 8)

      @__extdata = ''
      if @__extsize
        data = @fullRead @__extsize
        @__extdata = data.toString('hex')

  getFrameReader: (data, frames) ->
    # if ((this.version.majorRev < 4) && this.f_unsynch)
      # try: data = unsynch.decode(data)
      # except ValueError: pass

    if (3 <= @version.majorRev)
      bpi = @determineBPI data,frames
      reader = () => 
        loop
          try
            header = data[0...10]
            offset = 0
            
            name   = fromLatin1ToString header[offset...offset+=4]
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
    
    else if (2 <= @version.majorRev)
      reader = () =>
        loop
          try
            header = data[0...6]
            offset = 0 
            
            name   = fromLatin1ToString header[offset...offset+=3]
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

    if (@version.majorRev < 4) 
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
      name   = fromLatin1ToString part[0...4]
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
      name   = fromLatin1ToString part[0...4]
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

class Frame
  constructor: () ->
    Object.defineProperty(this, 'FrameID', { 
      enumerable: true, 
      get: () -> @constructor.name
    });

    Object.defineProperty(this, 'HashKey', { 
      enumerable: true, 
      get: () -> @FrameID
    });

    return this unless arguments.length > 0

    #TODO:
    if false
      blah = false
    #FIRSTPASS: if arguments.length == 1 and arguments[0] instanceof this 
    #if len(args)==1 and len(kwargs)==0 and isinstance(args[0], type(self))
      #other = args[0]
      #for checker in @framespec
        #val = checker.validate(self, getattr(other, checker.name))
        #setattr(self, checker.name, val)
    else
      #TODO: Treat first arg as opts hash in place of kwargs
      kwargs = arguments[0];

      #for checker, val in _.zip(@framespec, args)
        #setattr(self, checker.name, checker.validate(self, val))
        
      #for checker in @framespec[len(args):]
      for checker in @framespec
        validated = checker.validate(this, kwargs[checker.name])
        this[checker.name] = validated
        #Object.defineProperty(this, checker.name, validated)

        #validated = checker.validate(self, kwargs.get(checker.name, None))
        #setattr(self, checker.name, validated)

  _readData: (data) ->
    odata = data
    for spec in @framespec
      throw new Error('ID3JunkFrameError') unless data.length > 0
      ##try: value, data = reader.read(self, data)
      [value, data] = spec.read(this, data)
      ##except UnicodeDecodeError:
      ##raise ID3JunkFrameError
      this[spec.name] = value
          
    ##if data.strip('\x00'):
        ##warn('Leftover data: %s: %r (from %r)' % (
          ##type(self).__name__, data, odata),
      ##ID3Warning)

Frame.isValidFrameId = (frameId) -> 
  upperBound  = 'Z'.charCodeAt(0)
  lowerBound  = 'A'.charCodeAt(0)
  upperBound1 = '9'.charCodeAt(0)
  lowerBound1 = '0'.charCodeAt(0)

  isAlphaNumeric = true
  for i in [0..frameId.length]
    char = frameId.charCodeAt(i)
    if char <= upperBound and char >= lowerBound then continue
    else if char <= upperBound1 and char >= lowerBound1 then continue
    else isAlphaNumeric = false

  return isAlphaNumeric

Frame.fromData = (cls, id3, tflags, data) -> 

  if 4 <= id3.version.majorRev
    true
      ##if tflags & (Frame.FLAG24_COMPRESS | Frame.FLAG24_DATALEN):
          ## The data length int is syncsafe in 2.4 (but not 2.3).
          ## However, we don't actually need the data length int,
          ## except to work around a QL 0.12 bug, and in that case
          ## all we need are the raw bytes.
          ##datalen_bytes = data[:4]
          ##data = data[4:]
      ##if tflags & Frame.FLAG24_UNSYNCH or id3.f_unsynch:
          ##try: data = unsynch.decode(data)
          ##except ValueError, err:
              ##if id3.PEDANTIC:
                  ##raise ID3BadUnsynchData, '%s: %r' % (err, data)
      ##if tflags & Frame.FLAG24_ENCRYPT:
          ##raise ID3EncryptionUnsupportedError
      ##if tflags & Frame.FLAG24_COMPRESS:
          ##try: data = data.decode('zlib')
          ##except zlibError, err:
              ## the initial mutagen that went out with QL 0.12 did not
              ## write the 4 bytes of uncompressed size. Compensate.
              ##data = datalen_bytes + data
              ##try: data = data.decode('zlib')
              ##except zlibError, err:
                  ##if id3.PEDANTIC:
                      ##raise ID3BadCompressedData, '%s: %r' % (err, data)

  else if 3 <= id3.version.majorRev
    true
      ##if tflags & Frame.FLAG23_COMPRESS:
          ##usize, = unpack('>L', data[:4])
          ##data = data[4:]
      ##if tflags & Frame.FLAG23_ENCRYPT:
          ##raise ID3EncryptionUnsupportedError
      ##if tflags & Frame.FLAG23_COMPRESS:
          ##try: data = data.decode('zlib')
          ##except zlibError, err:
              ##if id3.PEDANTIC:
                  ##raise ID3BadCompressedData, '%s: %r' % (err, data)

  frame = new cls()
  frame._rawdata = data
  ##frame._flags = tflags
  frame._readData(data)
  return frame

class Spec
  constructor: (name) -> 
    @name = name

class ByteSpec extends Spec
  constructor: (name) ->
    return new ByteSpec(arguments...) unless this instanceof ByteSpec 
    super name

  read: (frame, data) -> 
    #TODO: Take a closer look at what we're doing here
    [ data.toString('utf8', 0, 1).charCodeAt(0), data[1..] ]
    ## return ord(data[0]), data[1:]

  validate: (frame, value) -> value
    
class EncodingSpec extends ByteSpec
  constructor: (name) ->
    return new EncodingSpec(arguments...) unless this instanceof EncodingSpec 
    super name

  read: (frame, data) ->
    [enc, data] = super arguments...
    if enc < 16 then [enc, data] else [0, String.fromCharCode(enc) + data]
    ## else: return 0, chr(enc)+data
  
  validate: (frame, value) -> 
    if 0 <= value <= 3 then return value
    if !value then return null
    throw new Error "Invalid Encoding: #{value}"

class MultiSpec extends Spec
  constructor: (name, specs..., sep) ->
    if this not instanceof MultiSpec
      ## Need a throwaway arg for applying to bind
      Array.prototype.unshift.call(arguments, null)
      return new (Function.prototype.bind.apply(MultiSpec, arguments))

    @specs = specs
    #TODO: Separator used in validate for mutagen?
    @sep = sep
    super name

  read: (frame, data) -> 
    values = []
  
    while data.length
      record = []
      for spec in @specs
        [value, data] = spec.read(frame, data)
        record.push value
      
      if @specs.length isnt 1 then values.push record
      else values.push record[0]

    return [values, data]  

  validate: (frame, value) ->
    if !value then return []
    if @sep and _.isString(value)
      value = value.split(@sep)
    if _.isArray(value)
      if @specs.length is 1
        return (@specs[0].validate(frame, v) for v in value)
      #TODO:
      #else
        #return [ 
          #[s.validate(frame, v) for (v,s) in zip(val, @specs)]
          #for val in value ]
      throw new Error "Invalid MultiSpec data: #{value}"

class EncodedTextSpec extends Spec
  constructor: (name) ->
    return new EncodedTextSpec(arguments...) unless this instanceof EncodedTextSpec 
   
    @_encodings = [ 
      [ fromLatin1ToString, '00' ],
      [ fromUTF16ToString, '0000' ],
      [ fromUTF16BEToString, '0000' ],
      [ fromUTF8ToString, '00' ]
    ]
    super name

  read: (frame, data) -> 
    [decode, term] = @_encodings[frame.encoding]
    
    hexStr = data.toString 'hex'
    grouping = if term.length is 2 then /(.{2})/g else /(.{4})/g
    hexArr = hexStr.match grouping

    ret = ''
    offset = hexArr.indexOf term 
    if offset isnt -1
      stringOffset = offset * term.length
      [data, ret] = [ hexStr[0...stringOffset], hexStr[stringOffset+term.length..] ]
        
    data = new Buffer(data, 'hex') if typeof data is 'string'
    ret = new Buffer(ret, 'hex')

    if data.length < term.length then return ['', ret] 

    return [decode(data), ret]

  validate: (frame, value) -> value

#TODO: Since I used that cute constructor override trick to avoid calling new,
# I've created a different potential problem. In the event, I don't override the
# subclass constructor the object will be new-ed as a different type by the
# first overriden parent constructor. Either override all constructors in the
# inheritance chain or find some kind of functional craziness to dynamically
# invoke the correct constructor.
#
# Example:
#  console.log (EncodedNumericTextSpec('caca') instanceof EncodedNumericTextSpec)
#  console.log (EncodedNumericTextSpec('caca') instanceof EncodedTextSpec)
#
class EncodedNumericTextSpec extends EncodedTextSpec
class EncodedNumericPartTextSpec extends EncodedTextSpec

class ID3TimeStamp
  constructor: (text) ->

    Object.defineProperty this, 'text',
      enumerable: true
      get: () ->
        #TODO: Mutagen may have these in different scope. Perf implications?
        formats = ['%04d', '%02d', '%02d', '%02d', '%02d', '%02d'] 
        seps = ['-', '-', ' ', ':', ':', 'x']

        parts = [ @year, @month, @day, @hour, @minute, @second ]
        pieces = []
        for part,idx in parts when part isnt null
          pieces.push(sprintf(formats[idx], part) + seps[idx])
        pieces.join('')[...-1]
      set: (text) ->
        #TODO: Mutagen allows overriding regex
        splitre = /[-T:/.]|\s+/
        units = 'year month day hour minute second'.split(' ')
        values = (text + ':::::').split(splitre)[...6]
         
        for unit,v of _.object(units,values) 
          v = parseInt(v, 10)
          v = null if _.isNaN(v)
          this[unit] = v

    text = text.text if text instanceof ID3TimeStamp
    @text = text
 
  toString: () -> @text
  
  valueOf: () -> @text

class TimeStampSpec extends EncodedTextSpec
  constructor: (name) ->
    return new TimeStampSpec(arguments...) unless this instanceof TimeStampSpec 
    super name

  read: (frame, data) ->
    [ value, data ] = super arguments...
    return [ @validate(frame, value), data ]

  validate: (frame, value) ->
    try
      return new ID3TimeStamp(value)
    catch err
      throw new RangeError "Invalid ID3TimeStamp: #{value}"

class TextFrame extends Frame
  framespec: [ EncodingSpec('encoding'), MultiSpec('text', EncodedTextSpec('text'), sep='\u0000') ]

  toString: () -> @text.join '\u0000'
  
  valueOf: () -> @text
  
class NumericTextFrame extends TextFrame
  framespec: [ EncodingSpec('encoding'), MultiSpec('text', EncodedNumericTextSpec('text'), '\u0000') ]
  
  valueOf: () -> parseInt(@text[0], 10)

class NumericPartTextFrame extends TextFrame
  framespec: [ EncodingSpec('encoding'), MultiSpec('text', EncodedNumericPartTextSpec('text'), '\u0000') ]

  valueOf: () -> parseInt(@text[0].split('/')[0], 10)

class TimeStampTextFrame extends TextFrame
  framespec: [ EncodingSpec('encoding'), MultiSpec('text', TimeStampSpec('stamp'), sep=',') ]

  toString: () -> 
    (stamp.text for stamp in @text).join(',')

# v2.3
FRAMES = {
  "AENC" : "Audio encryption",
  "APIC" : "Attached picture",
  "COMM" : "Comments",
  "COMR" : "Commercial frame",
  "ENCR" : "Encryption method registration",
  "EQUA" : "Equalization",
  "ETCO" : "Event timing codes",
  "GEOB" : "General encapsulated object",
  "GRID" : "Group identification registration",
  "IPLS" : "Involved people list",
  "LINK" : "Linked information",
  "MCDI" : "Music CD identifier",
  "MLLT" : "MPEG location lookup table",
  "OWNE" : "Ownership frame",
  "PRIV" : "Private frame",
  "PCNT" : "Play counter",
  "POPM" : "Popularimeter",
  "POSS" : "Position synchronisation frame",
  "RBUF" : "Recommended buffer size",
  "RVAD" : "Relative volume adjustment",
  "RVRB" : "Reverb",
  "SYLT" : "Synchronized lyric/text",
  "SYTC" : "Synchronized tempo codes",
  "TCON" : "Content type",
  "TDLY" : "Playlist delay",
  "TENC" : "Encoded by",
  "TEXT" : "Lyricist/Text writer",
  "TFLT" : "File type",
  "TKEY" : "Initial key",
  "TLAN" : "Language(s)",
  "TMED" : "Media type",
  "TOAL" : "Original album/movie/show title",
  "TOFN" : "Original filename",
  "TOLY" : "Original lyricist(s)/text writer(s)",
  "TOPE" : "Original artist(s)/performer(s)",
  "TORY" : "Original release year",
  "TOWN" : "File owner/licensee",
  "TPUB" : "Publisher",
  "TRDA" : "Recording dates",
  "TRSN" : "Internet radio station name",
  "TRSO" : "Internet radio station owner",
  "TSIZ" : "Size",
  "TSRC" : "ISRC (international standard recording code)",
  "TSSE" : "Software/Hardware and settings used for encoding",
  "TXXX" : "User defined text information frame",
  "UFID" : "Unique file identifier",
  "USER" : "Terms of use",
  "USLT" : "Unsychronized lyric/text transcription",
  "WCOM" : "Commercial information",
  "WCOP" : "Copyright/Legal information",
  "WOAF" : "Official audio file webpage",
  "WOAR" : "Official artist/performer webpage",
  "WOAS" : "Official audio source webpage",
  "WORS" : "Official internet radio station homepage",
  "WPAY" : "Payment",
  "WPUB" : "Publishers official webpage",
  "WXXX" : "User defined URL link frame"
}

# Workaround since we still need a complete
# lookup for determineBPI. Will eventually
# replace FRAMES entirely.
$FRAMES = [
  class TALB extends TextFrame,            # Album/Movie/Show title
  class TBPM extends NumericTextFrame,     # BPM (beats per minute)
  class TCOM extends TextFrame,            # Composer
  class TCOP extends TextFrame,            # Copyright message
  class TCMP extends NumericTextFrame,     # iTunes Compilation Flag
  class TDAT extends TextFrame,            # Date of recording (DDMM)
  class TDRC extends TimeStampTextFrame,   # Recording Time
  class TIME extends TextFrame,            # Time of recording (HHMM)
  class TLEN extends NumericTextFrame,     # Length
  class TIT1 extends TextFrame,            # Content group description
  class TIT2 extends TextFrame,            # Title/songname/content description
  class TIT3 extends TextFrame,            # Conductor/performer refinement
  class TPE1 extends TextFrame,            # Lead performer(s)/Soloist(s)
  class TPE2 extends TextFrame,            # Band/orchestra/accompaniment
  class TPE3 extends TextFrame,            # Conductor
  class TPE4 extends TextFrame,            # Interpreter/remixer/modifier
  class TPOS extends NumericPartTextFrame, # Part of a set
  class TRCK extends NumericPartTextFrame, # Track number/Position in set
  class TYER extends NumericTextFrame,     # Year
  class TDEN extends TimeStampTextFrame,   # Encoding Time
  class TDOR extends TimeStampTextFrame,   # Original Release Time
  class TDRC extends TimeStampTextFrame,   # Recording Time
  class TDRL extends TimeStampTextFrame,   # Release Time
  class TDTG extends TimeStampTextFrame    # Tagging Time
]

for cls in $FRAMES
  FRAMES[cls] = cls

FRAMES_2_2 = {
  # v2.2
  "BUF" : "Recommended buffer size",
  "CNT" : "Play counter",
  "COM" : "Comments",
  "CRA" : "Audio encryption",
  "CRM" : "Encrypted meta frame",
  "ETC" : "Event timing codes",
  "EQU" : "Equalization",
  "GEO" : "General encapsulated object",
  "IPL" : "Involved people list",
  "LNK" : "Linked information",
  "MCI" : "Music CD Identifier",
  "MLL" : "MPEG location lookup table",
  "PIC" : "Attached picture",
  "POP" : "Popularimeter",
  "REV" : "Reverb",
  "RVA" : "Relative volume adjustment",
  "SLT" : "Synchronized lyric/text",
  "STC" : "Synced tempo codes",
  "TCO" : "Content type",
  "TDY" : "Playlist delay",
  "TEN" : "Encoded by",
  "TFT" : "File type",
  "TKE" : "Initial key",
  "TLA" : "Language(s)",
  "TMT" : "Media type",
  "TOA" : "Original artist(s)/performer(s)",
  "TOF" : "Original filename",
  "TOL" : "Original Lyricist(s)/text writer(s)",
  "TOR" : "Original release year",
  "TOT" : "Original album/Movie/Show title",
  "TPB" : "Publisher",
  "TRC" : "ISRC (International Standard Recording Code)",
  "TRD" : "Recording dates",
  "TSI" : "Size",
  "TSS" : "Software/hardware and settings used for encoding",
  "TXT" : "Lyricist/text writer",
  "TXX" : "User defined text information frame",
  "UFI" : "Unique file identifier",
  "ULT" : "Unsychronized lyric/text transcription",
  "WAF" : "Official audio file webpage",
  "WAR" : "Official artist/performer webpage",
  "WAS" : "Official audio source webpage",
  "WCM" : "Commercial information",
  "WCP" : "Copyright/Legal information",
  "WPB" : "Publishers official webpage",
  "WXX" : "User defined URL link frame",
}

$FRAMES_2_2 = [
  class TAL extends TALB,    # Album/Movie/Show title
  class TBP extends TBPM,    # BPM (beats per minute)
  class TCM extends TCOM,    # Composer
  class TCR extends TCOP,    # Copyright message
  class TCO extends TCMP,    # iTunes Compilation Flag
  class TDA extends TDAT,    # Date of recording (DDMM)
  class TIM extends TIME,    # Time of recording (HHMM)
  class TLE extends TLEN,    # Length
  class TT1 extends TIT1,    # Content group description
  class TT2 extends TIT2,    # Title/songname/content description
  class TT3 extends TIT3,    # Conductor/performer refinement
  class TP1 extends TPE1,    # Lead performer(s)/Soloist(s)
  class TP2 extends TPE2,    # Band/orchestra/accompaniment
  class TP3 extends TPE3,    # Conductor
  class TP4 extends TPE4,    # Interpreter/remixer/modifier
  class TPA extends TPOS,    # Part of a set
  class TRK extends TRCK,    # Track number/Position in set
  class TYE extends TYER     # Year
]
for cls in $FRAMES_2_2
  FRAMES_2_2[cls] = cls

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
    tag = fromLatin1ToString buffer[offset...offset+=3]
    title = fromLatin1ToString buffer[offset...offset+=30]
    artist = fromLatin1ToString buffer[offset...offset+=30]
    album = fromLatin1ToString buffer[offset...offset+=30]
    year = fromLatin1ToString buffer[offset...offset+=(tagByteLength - 124)]
    comment = fromLatin1ToString buffer[offset...offset+=29]
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
  frames["TIT2"] = new TIT2({encoding:0, text:title}) if title
  frames["TPE1"] = new TPE1({encoding:0, text:[artist]}) if artist
  frames["TALB"] = new TALB({encoding:0, text:album}) if album
  frames["TDRC"] = new TDRC({encoding:0, text:year}) if year
  #if comment: frames["COMM"] = COMM(
    #encoding=0, lang="eng", desc="ID3v1 Comment", text=comment)
  # Don't read a track number if it looks like the comment was
  # padded with spaces instead of nulls (thanks, WinAmp).
  if track and (track != 32 or hexString[-6..-5] == '00')
    frames["TRCK"] = new TRCK({encoding:0, text:track.toString()})
  #if genre != 255: frames["TCON"] = TCON(encoding=0, text=str(genre))
  
  return frames
