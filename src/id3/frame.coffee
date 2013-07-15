sprintf = require("sprintf-js").sprintf

convert = require '../text-encodings'
unsynch = require './unsynch'

{ValueError, UnicodeDecodeError} = require '../errors'
{ID3JunkFrameError, ID3BadUnsynchData} = require './errors'

FLAG23_ALTERTAG     = 0x8000
FLAG23_ALTERFILE    = 0x4000
FLAG23_READONLY     = 0x2000
FLAG23_COMPRESS     = 0x0080
FLAG23_ENCRYPT      = 0x0040
FLAG23_GROUP        = 0x0020

FLAG24_ALTERTAG     = 0x4000
FLAG24_ALTERFILE    = 0x2000
FLAG24_READONLY     = 0x1000
FLAG24_GROUPID      = 0x0040
FLAG24_COMPRESS     = 0x0008
FLAG24_ENCRYPT      = 0x0004
FLAG24_UNSYNCH      = 0x0002
FLAG24_DATALEN      = 0x0001

# Utility functions
isString = (a) -> Object.prototype.toString.call(a) == "[object String]"
isArray = require('util').isArray

# Fundamental unit of ID3 data.

# ID3 tags are split into frames. Each frame has a potentially
# different structure, and so this base class is not very featureful.
class Frame
  
  nullChars = ///
    ^ (?: 0{2} )+    |  # leading null characters [00] in hex
      (?: 0{2} )+ $     # trailing null chars [00] in hex
  ///g

  # fields should be a plain object with named properties corresponding to the
  # framespec
  constructor: (fields) ->
    Object.defineProperty(this, 'FrameID', {
      enumerable: true,
      get: () -> @constructor.name
    });

    Object.defineProperty(this, 'HashKey', {
      configurable: true,
      enumerable: true,
      get: () -> @FrameID
    });

    return this unless arguments.length > 0

    for checker in @framespec
      validated = checker.validate(this, fields[checker.name])
      this[checker.name] = validated

  _readData: (data) ->
    odata = data
    for spec in @framespec
      throw new ID3JunkFrameError unless data.length > 0
      
      try
        [value, data] = spec.read(this, data)
      catch err
        throw err unless err instanceof UnicodeDecodeError
        throw new ID3JunkFrameError

      this[spec.name] = value

    if data.toString('hex').replace(nullChars, '')
      console.warn "Leftover data: #{@FrameID}: ", data, " (from ", odata, ")"

Frame.toString = () -> @name

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

  if 4 <= id3.version.minor
    throw new ID3EncryptionUnsupportedError if tflags & FLAG24_ENCRYPT

    if tflags & (FLAG24_COMPRESS | FLAG24_DATALEN)
      ## The data length int is syncsafe in 2.4 (but not 2.3).
      ## However, we don't actually need the data length int,
      ## except to work around a QL 0.12 bug, and in that case
      ## all we need are the raw bytes.
      datalen_bytes = data[...4]
      data = data[4..]
    
    if tflags & FLAG24_UNSYNCH or id3.f_unsynch
      try
        data = unsynch.decode(data)
      catch err
        throw err unless err instanceof ValueError
        throw new ID3BadUnsynchData "#{err.message}: #{data}" if id3.PEDANTIC

    if tflags & FLAG24_COMPRESS
      true
      #TODO: Need to add async support up the callchain or find synchronous zlib 
      #zlib = require 'zlib'
      #zlib.inflate data, (err, result) ->
        #if not err
          #data = result
          #return

        ## the initial mutagen that went out with QL 0.12 did not
        ## write the 4 bytes of uncompressed size. Compensate.
        #data = Buffer.concat(datalen_bytes, data)
        #zlib.inflate data, (err, result) ->
          #throw new ID3BadCompressedData "#{err.message}: #{data}" if err and id3.PEDANTIC
          #data = result

  else if 3 <= id3.version.minor
    throw new ID3EncryptionUnsupportedError if tflags & FLAG23_ENCRYPT
    true
      ##if tflags & Frame.FLAG23_COMPRESS:
          ##usize, = unpack('>L', data[:4])
          ##data = data[4:]
      ##if tflags & Frame.FLAG23_COMPRESS:
          ##try: data = data.decode('zlib')
          ##except zlibError, err:
              ##if id3.PEDANTIC:
                  ##raise ID3BadCompressedData, '%s: %r' % (err, data)

  frame = new cls()
  frame._rawdata = data
  frame._flags = tflags
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
    throw new ValueError "Invalid Encoding: #{value}"


class StringSpec extends Spec
  constructor: (name, length) ->
    return new StringSpec(arguments...) unless this instanceof StringSpec

    @len = length
    super name

  read: (frame, data) ->
    #return data[:s.len], data[s.len:]
    [ data[...@len], data[@len..] ]

  validate: (frame, value) ->
    return null unless value?

    return value if isString(value) and value.length == @len

    throw new ValueError sprintf('Invalid StringSpec[%d] data: %s', @len, value)

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
    if @sep and isString(value)
      value = value.split(@sep)
    if isArray(value)
      if @specs.length is 1
        return (@specs[0].validate(frame, v) for v in value)
      #TODO:
      #else
        #return [
          #[s.validate(frame, v) for (v,s) in zip(val, @specs)]
          #for val in value ]
      throw new ValueError "Invalid MultiSpec data: #{value}"

class EncodedTextSpec extends Spec

  @_encodings = [
    [ 'latin1'  , '00' ],
    [ 'utf16'   , '0000' ],
    [ 'utf16be' , '0000' ],
    [ 'utf8'    , '00' ]
  ]

  constructor: (name) ->
    return new EncodedTextSpec(arguments...) unless this instanceof EncodedTextSpec
    super name

  read: (frame, data) ->
    [encoding, term] = EncodedTextSpec._encodings[frame.encoding]

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

    if data.length < (term.length / 2) then return ['', ret]

    return [(convert data).from(encoding), ret]

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

## A time stamp in ID3v2 format.
 
## This is a restricted form of the ISO 8601 standard; time stamps
## take the form of:
##     YYYY-MM-DD HH:MM:SS
## Or some partial form (YYYY-MM-DD HH, YYYY, etc.).
## 
## The 'text' attribute contains the raw text data of the time stamp.
##
class ID3TimeStamp
  
  formats = ['%04d', '%02d', '%02d', '%02d', '%02d', '%02d']
  seps = ['-', '-', ' ', ':', ':', 'x']

  # parseInt allows some garbage that doesn't fly with Python's int. For
  # example, '12.aW123' will be truncated and coerced to a number. NaN is only
  # returned if first character cannot be converted to a number. This regex
  # from the MDN tightens things up a bit.
  strictInt = /^\-?([0-9]+|Infinity)$/
        
  #TODO: Mutagen allows overriding regex
  splitre = /[-T:/.]|\s+/

  constructor: (text) ->

    Object.defineProperty this, 'text',
      enumerable: true
      get: () ->
        parts = [ @year, @month, @day, @hour, @minute, @second ]
        pieces = []
        for part,idx in parts when part isnt null
          pieces.push(sprintf(formats[idx], part) + seps[idx])
        pieces.join('')[...-1]
 
      set: (text) ->
        [ year, month, day, hour, minute, second ] = 
          (text + ':::::').split(splitre)[...6]
        values = { year, month, day, hour, minute, second } 

        for unit,v of values
          v = parseInt(v, 10)
          v = null if Number.isNaN(v) or not strictInt.test(v)
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
      throw new ValueError "Invalid ID3TimeStamp: #{value}"

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
  framespec: [ EncodingSpec('encoding'), MultiSpec('text', TimeStampSpec('stamp'), ',') ]

  toString: () ->
    (stamp.text for stamp in @text).join(',')

##
## User comment.
##
## User comment frames have a descrption, like TXXX, and also a three letter
## ISO language code in the 'lang' attribute.
##
class COMM extends TextFrame
  framespec: [
    EncodingSpec('encoding'),
    StringSpec('lang', 3),
    EncodedTextSpec('desc'),
    MultiSpec('text', EncodedTextSpec('text'), '\u0000')
  ]

  constructor: () ->
    super
    Object.defineProperty(this, 'HashKey', {
      enumerable: true,
      #TODO: Mutagen uses format string %s:%s:%r which yields a repr for lang.
      # My guess is this may be used for writes, so I'm unsure if neccessary
      # here.
      get: () -> sprintf('%s:%s:%s', @FrameID, @desc, @lang)
    });
    
## Content type (Genre)

## ID3 has several ways genres can be represented; for convenience,
## use the 'genres' property rather than the 'text' attribute.
class TCON extends TextFrame

    GENRES = require('./constants').GENRES

    strDigits = ( digit.toString() for digit in [0..9] )
    genre_re = /((?:\(([0-9]+|RX|CR)\))*)(.+)?/
    startsWithParens = /^\(\(/

    constructor: () ->
      super

      # A list of genres parsed from the raw text data.
      Object.defineProperty(this, 'genres', {
        get: @__get_genres,
        set: @__set_genres
      });

    __get_genres: ->
      genres = []

      @text.forEach (value) ->
        notDigits = ( d for d in value when d not in strDigits )
        if value and notDigits.length is 0
          idx = (+value)
          genres.push (GENRES[idx] || 'Unknown')
        else if value is 'CR'
          genres.push 'Cover'
        else if value is 'RX'
          genres.push 'Remix'
        else if value
          newGenres = []
          [ wholematch, genreid, dummy, genrename ] = value.match(genre_re)

          if genreid
            gids = ( gid for gid in genreid[1...-1].split(')(') )
            gids.forEach (gid) ->
              idx = (+gid)
              notDigits = ( d for d in gid when d not in strDigits )
              if notDigits.length is 0 and idx < GENRES.length
                #gid = unicode(GENRES[int(gid)])
                gid = GENRES[idx]
                newGenres.push gid
              else if gid is "CR" then newGenres.push 'Cover'
              else if gid is "RX" then newGenres.push 'Remix'
              else
                newGenres.push 'Unknown'

          if genrename
            # "Unescaping" the first parenthesis
            if startsWithParens.test(genrename) then genrename = genrename[1..]
            if genrename not in newGenres then newGenres.push genrename

          genres = (genres.concat newGenres)

      return genres

    __set_genres: (genres) ->
      genres = [genres] if isString(genres)
      @text = ( genre for genre in genres )

      # TODO: Fairly certain that this is unneeded (at least for now. Unlike
      # Python, JS is only concerned with encodings when we begin dealing with
      # Buffers or sending files over the wire.
      #@text = ( @__decode genre for genre in genres )

    __decode: (value) ->
      #if isinstance(value, str):
        #enc = EncodedTextSpec._encodings[self.encoding][0]
        #return value.decode(enc)
      #else: return value

      if not isString(value) then return value

      enc = EncodedTextSpec._encodings[@encoding][0]
      return (convert value).from(enc)

# v2.3
FRAMES = {
  "AENC" : "Audio encryption",
  "APIC" : "Attached picture",
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
  class TDTG extends TimeStampTextFrame,   # Tagging Time
  COMM,                                    # Comments
  TCON                                     # Content type
]

for cls in $FRAMES
  FRAMES[cls] = cls

FRAMES_2_2 = {
  # v2.2
  "BUF" : "Recommended buffer size",
  "CNT" : "Play counter",
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
  class TYE extends TYER,    # Year
  class COM extends COMM,    # Comments
  class TCO extends TCON     # Content type
]
for cls in $FRAMES_2_2
  FRAMES_2_2[cls] = cls

Frame.FRAMES = FRAMES
Frame.FRAMES_2_2 = FRAMES_2_2

module.exports = Frame
