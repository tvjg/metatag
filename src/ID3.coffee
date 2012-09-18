fs = require 'fs'
_  = require 'underscore'

BitPaddedInt = require('./BitPaddedInt.js')

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
        #Skip until frame reader is complete
        #headerLoaded = true
      catch err
        #TODO: Handle failure to load tag header
        console.log err
      finally
        if headerLoaded
          if @version.majorRev >= 3      then frames = FRAMES
          else if @version.majorRev <= 2 then frames = FRAMES_2_2
        
          data      = @fullRead (@size - 10)
          readFrame = @getFrameReader data,frames
          frame     = do readFrame
          while frame isnt false
            if frame instanceof Frame then @frames.push frame
            else if frame?            then @unknownFrames.push frame

    finally
      fs.closeSync @__fileobj
      @__fileobj  = null
      @__filesize = null

  loadHeader: () ->
    data = @fullRead 10
    
    offset = 0
    id3 = data.toString('utf8', offset, offset+=3)

    @version = {
      majorRev : data.readUInt8(offset++)
      minorRev : data.readUInt8(offset++)
    }
  
    flags = data.readUInt8(offset++)
    @f_unsynch      = ((flags & 0x80) != 0) 
    @f_extended     = ((flags & 0x40) != 0)
    @f_experimental = ((flags & 0x20) != 0)
    @f_footer       = ((flags & 0x10) != 0)
    
    sizeRepr = data.toString('utf8', offset, offset+=4)
    @size = BitPaddedInt(sizeRepr) + 10;

    throw new Error("#{@filepath} doesn't start with an ID3 tag") unless id3 is 'ID3'
    throw new Error("#{@filepath} ID3v2.#{@version.majorRev} not supported") unless @version.majorRev in [2,3,4]

    if @f_extended
      data = @fullRead 4
      extSizeRepr = data.toString('utf8')
    
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

module.exports = ID3

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
  "TIT2" : "Title/songname/content description",
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
  "TYER" : "Year", #NumericTextFrame
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
