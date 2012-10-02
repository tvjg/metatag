fs = require 'fs'
_  = require 'underscore'
Iconv = require('iconv').Iconv

BitPaddedInt = require('./BitPaddedInt.js')

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
    @frames        = []
    @unknownFrames = []

    @load(filepath) if filepath?

  fullRead: (size) ->
    throw new Error "Requested bytes #{size} less than zero" if (size < 0)
    throw new Error "Requested #{size} of #{@__filesize} #{@filepath}" if (size > @__filesize)

    buff = new Buffer size
    bytesRead = fs.readSync @__fileobj, buff, 0, size, @__readbytes

    throw new Error 'End of file' if bytesRead isnt size

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
        #TODO: Handle failure to load tag header
        console.log err
      finally
        if headerLoaded
          if @version.majorRev >= 3      then frames = FRAMES
          else if @version.majorRev <= 2 then frames = FRAMES_2_2
        
          data      = @fullRead (@size - 10)
          readFrame = @getFrameReader data,frames
          frame     = false
          while (frame = do readFrame) isnt false
            #TODO: Instead of adding to array add to self under frame name
            if frame instanceof Frame then @frames.push frame
            else if frame?            then @unknownFrames.push frame

    finally
      fs.closeSync @__fileobj
      @__fileobj  = null
      @__filesize = null

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

    throw new Error("#{@filepath} doesn't start with an ID3 tag") unless id3 is 'ID3'
    throw new Error("#{@filepath} ID3v2.#{@version.majorRev} not supported") unless @version.majorRev in [2,3,4]

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
            console.log err
            # not enough header
            return false 

          if ((name.replace(/[\x00]+$/g, '')) == '') then return false

          size      = bpi(size)
          framedata = data[10...10+size]
          data      = data[10+size..]
          
          break unless (size == 0) # drop empty frames

        frameSpec = frames[name]
        #if (frameSpec === undefined) {
        #TODO: Temporary hackaround while we're defining specs
        if not _.isArray(frameSpec)
          if Frame.isValidFrameId(name) then return header + framedata
        else
          return Frame.loadFramedata(this, frameSpec, flags, framedata)
          ## try: yield self.__load_framedata(tag, flags, framedata)
          ## except NotImplementedError: yield header + framedata
          ## except ID3JunkFrameError: pass
    
    else if (2 <= @version.majorRev)
      while data.length
        try
          header = data[0...6]
          offset = 0 
          
          name   = fromLatin1ToString header[offset...offset+=3]
          size   = fromLatin1ToString header[offset...offset+=3]
        catch err
          console.log err
          # not enough header
          return false
        ## size, = struct.unpack('>L', '\x00'+size)
        if ((name.replace(/[\x00]+$/g, '')) == '') then return false
        ## framedata = data[6:6+size]
        ## data = data[6+size:]
        ## if size == 0: continue # drop empty frames
        ## try: tag = frames[name]
        ## except KeyError:
            ## if is_valid_frame_id(name): yield header + framedata
        ## else:
            ## try: yield self.__load_framedata(tag, 0, framedata)
            ## except NotImplementedError: yield header + framedata
            ## except ID3JunkFrameError: pass

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
  constructor: (frameSpecs, data) ->
    odata = data
    for spec in frameSpecs
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

Frame.loadFramedata = (id3, frameSpecs, tflags, data) -> 

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

  frame = new Frame(frameSpecs, data)
  frame._rawdata = data
  ##frame._flags = tflags
  ##frame._readData(data)
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
    
class EncodingSpec extends ByteSpec
  constructor: (name) ->
    return new EncodingSpec(arguments...) unless this instanceof EncodingSpec 
    super name

  read: (frame, data) ->
    [enc, data] = super arguments...
    if enc < 16 then [enc, data] else [0, String.fromCharCode(enc) + data]
    ## else: return 0, chr(enc)+data

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
    
    ret = ''
    offset = -1
    hexStr = data.toString 'hex'
    grouping = if term.length is 2 then /(.{2})/g else /(.{4})/g

    hexArr = hexStr.match grouping
    offset = hexArr.indexOf term 
    if offset isnt -1
      stringOffset = offset * term.length
      [data, ret] = [ hexStr[0...stringOffset], hexStr[stringOffset+term.length..] ]
        
    data = new Buffer(data, 'hex') if typeof data is 'string'
    ret = new Buffer(ret, 'hex')

    if data.length < term.length then return ['', ret] 

    return [decode(data), ret]

class EncodedNumericTextSpec extends EncodedTextSpec

TextFrame = [ EncodingSpec('encoding'), MultiSpec('text', EncodedTextSpec('text'), sep='\u0000') ]
  
NumericTextFrame = [ EncodingSpec('encoding'), MultiSpec('text', EncodedNumericTextSpec('text'), '\u0000') ]

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
  "TAL" : "Album/Movie/Show title",
  "TBP" : "BPM (Beats Per Minute)",
  "TCM" : "Composer",
  "TCO" : "Content type",
  "TCR" : "Copyright message",
  "TDA" : "Date",
  "TDY" : "Playlist delay",
  "TEN" : "Encoded by",
  "TFT" : "File type",
  "TIM" : "Time",
  "TKE" : "Initial key",
  "TLA" : "Language(s)",
  "TLE" : "Length",
  "TMT" : "Media type",
  "TOA" : "Original artist(s)/performer(s)",
  "TOF" : "Original filename",
  "TOL" : "Original Lyricist(s)/text writer(s)",
  "TOR" : "Original release year",
  "TOT" : "Original album/Movie/Show title",
  "TP1" : "Lead artist(s)/Lead performer(s)/Soloist(s)/Performing group",
  "TP2" : "Band/Orchestra/Accompaniment",
  "TP3" : "Conductor/Performer refinement",
  "TP4" : "Interpreted, remixed, or otherwise modified by",
  "TPA" : "Part of a set",
  "TPB" : "Publisher",
  "TRC" : "ISRC (International Standard Recording Code)",
  "TRD" : "Recording dates",
  "TRK" : "Track number/Position in set",
  "TSI" : "Size",
  "TSS" : "Software/hardware and settings used for encoding",
  "TT1" : "Content group description",
  "TT2" : "Title/Songname/Content description",
  "TT3" : "Subtitle/Description refinement",
  "TXT" : "Lyricist/text writer",
  "TXX" : "User defined text information frame",
  "TYE" : "Year",
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

FRAMES = {
  # v2.3
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
  "TALB" : "Album/Movie/Show title",
  "TBPM" : "BPM (beats per minute)",
  "TCOM" : "Composer",
  "TCON" : "Content type",
  "TCOP" : "Copyright message",
  "TDAT" : "Date",
  "TDLY" : "Playlist delay",
  "TENC" : "Encoded by",
  "TEXT" : "Lyricist/Text writer",
  "TFLT" : "File type",
  "TIME" : "Time",
  "TIT1" : "Content group description",
  "TIT2" : TextFrame, # "Title/songname/content description",
  "TIT3" : "Subtitle/Description refinement",
  "TKEY" : "Initial key",
  "TLAN" : "Language(s)",
  "TLEN" : "Length",
  "TMED" : "Media type",
  "TOAL" : "Original album/movie/show title",
  "TOFN" : "Original filename",
  "TOLY" : "Original lyricist(s)/text writer(s)",
  "TOPE" : "Original artist(s)/performer(s)",
  "TORY" : "Original release year",
  "TOWN" : "File owner/licensee",
  "TPE1" : "Lead performer(s)/Soloist(s)",
  "TPE2" : "Band/orchestra/accompaniment",
  "TPE3" : "Conductor/performer refinement",
  "TPE4" : "Interpreted, remixed, or otherwise modified by",
  "TPOS" : "Part of a set",
  "TPUB" : "Publisher",
  "TRCK" : "Track number/Position in set",
  "TRDA" : "Recording dates",
  "TRSN" : "Internet radio station name",
  "TRSO" : "Internet radio station owner",
  "TSIZ" : "Size",
  "TSRC" : "ISRC (international standard recording code)",
  "TSSE" : "Software/Hardware and settings used for encoding",
  "TYER" : NumericTextFrame, # "Year"
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
