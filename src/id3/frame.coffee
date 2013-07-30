Q       = require('q')
sprintf = require("sprintf-js").sprintf

convert = require '../text-encodings'
unsynch = require './unsynch'

{ValueError, UnicodeDecodeError} = require '../errors'
{ID3JunkFrameError, ID3BadUnsynchData} = require './errors'

{
  ByteSpec, EncodingSpec, StringSpec, MultiSpec
  EncodedTextSpec, EncodedNumericTextSpec
  EncodedNumericPartTextSpec, TimeStampSpec
  Latin1TextSpec, BinaryDataSpec
} = require './framespecs'

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

isUpperCaseAlphanumeric = /^[A-Z0-9]+$/
Frame.isValidFrameId = (frameId) -> isUpperCaseAlphanumeric.test(frameId)

Frame.fromData = (cls, id3, tflags, data) ->

  makeFrame = (data) ->
    frame = new cls()
    frame._rawdata = data
    frame._flags = tflags
    frame._readData(data)
    return frame

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
      zlib = require 'zlib'

      return Q
        .nfcall(zlib.inflate, data)
        .fail (err) ->
          # the initial mutagen that went out with QL 0.12 did not
          # write the 4 bytes of uncompressed size. Compensate.
          data = Buffer.concat([datalen_bytes, data])
          Q.nfcall(zlib.inflate, data)
        .then (inflatedData) ->
          (makeFrame inflatedData)
        .fail (err) ->
          throw new ID3BadCompressedData "#{err.message}: #{data}" if err and id3.PEDANTIC

  else if 3 <= id3.version.minor
    throw new ID3EncryptionUnsupportedError if tflags & FLAG23_ENCRYPT

    if tflags & FLAG23_COMPRESS
      zlib = require 'zlib'

      #TODO: Unsure why Mutagen unpacks and never uses this
       ##usize, = unpack('>L', data[:4])
      data = data[4..]
      return Q
        .nfcall(zlib.inflate, data)
        .then (inflatedData) ->
          (makeFrame inflatedData)
        .fail (err) ->
          throw new ID3BadCompressedData "#{err.message}: #{data}" if err and id3.PEDANTIC

  return Q.fcall(makeFrame, data)

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
      get: () -> sprintf('%s:%s:%s', @FrameID, @desc || 'None', @lang || 'None')
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

# Attached (or linked) Picture.
#
# Attributes:
# encoding -- text encoding for the description
# mime -- a MIME type (e.g. image/jpeg) or '-->' if the data is a URI
# type -- the source of the image (3 is the album front cover)
# desc -- a text description of the image
# data -- raw image data, as a byte string
#
# Mutagen will automatically compress large images when saving tags.
class APIC extends Frame
  framespec: [
    EncodingSpec('encoding'),
    Latin1TextSpec('mime'),
    ByteSpec('type'),
    EncodedTextSpec('desc'),
    BinaryDataSpec('data')
  ]

# v2.3
FRAMES = {
  "AENC" : "Audio encryption",
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
  APIC,                                     # Attached picture
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

module.exports =
  {Frame, TextFrame, NumericTextFrame, NumericPartTextFrame, TimeStampTextFrame}
