vows   = require('vows');
should = require('should');

ID3 = require('../lib/id3');
F   = require('../lib/id3/frame');

Frame                = F.Frame;
TextFrame            = F.TextFrame;
NumericTextFrame     = F.NumericTextFrame;
NumericPartTextFrame = F.NumericPartTextFrame;

convert = require('../lib/text-encodings');

_22 = new ID3(); _22.version = { major: 2, minor: 2, sub: 0 }
_23 = new ID3(); _23.version = { major: 2, minor: 3, sub: 0 }
_24 = new ID3(); _24.version = { major: 2, minor: 4, sub: 0 }

// TT1 test framedata
_buff1           = new Buffer('54543100008300','hex');
_buff2           = new Buffer(Array(16).join('123456789abcdef'));
buff22DirectInts = Buffer.concat([_buff1, _buff2]);

vows
  .describe('Frame Sanity Checks')
  .addBatch({
    'A TextFrame initialized with {text: \'text\'}': {
      topic: new TextFrame({text:'text'}),
      'should be an instance of TextFrame': function (frame) {
	frame.should.be.an.instanceOf(TextFrame);
      }
    },
    'A NumericTextFrame initialized with {text: \'1\'}': {
      topic: new NumericTextFrame({text:'1'}),
      'should be an instance of NumericTextFrame': function (frame) {
        frame.should.be.an.instanceOf(NumericTextFrame);
      }
    },
    'A NumericPartTextFrame initialized with {text: \'1/2\'}': {
      topic: new NumericPartTextFrame({text:'1/2'}),
      'should be an instance of NumericPartTextFrame': function (frame) {
        frame.should.be.an.instanceOf(NumericPartTextFrame);
      }
    },
    'A TextFrame initialized with {text: \'[\'a\',\'b\']\'}': {
      topic: new TextFrame({text:['a','b']}),
      'should be an instance of TextFrame': function (frame) {
	frame.should.be.an.instanceOf(TextFrame);
      }
    },
    // Mutagen uses the rather cryptic test name test_22_uses_direct_ints. I
    // believe this relates to 2.2 using unpadded ints, but I'm not clear on
    // how exactly this relates to the provided test data.
    'A TT1 frame in a v2.2 tag': {
      topic: function () {
        var id3 = new ID3();
        id3.version = { major: 2, minor: 2, sub: 0 };

        var readFrame = id3.getFrameReader(buff22DirectInts, Frame.FRAMES_2_2);
        var loadingFrames = [], frame = false;
        while (frame = readFrame()) {
          loadingFrames.push(frame);
        }

        loadingFrames[0].nodeify(this.callback);
      },
      'should decode properly using unpadded ints': function (err, frame) {
        var expected = convert(buff22DirectInts.slice(7, 7+0x82)).from('latin1');
        frame.text[0].should.be.eql(expected);
      }
    },
    'A frame without enough data to parse a header': {
      topic: function () {
        var readers = [
          _24.getFrameReader(new Buffer('012345678'), Frame.FRAMES),
          _23.getFrameReader(new Buffer('012345678'), Frame.FRAMES),
          _22.getFrameReader(new Buffer('01234'), Frame.FRAMES_2_2),
          _22.getFrameReader(new Buffer('545431000000','hex'), Frame.FRAMES_2_2)
        ];

        var loadingFrames = [], frame = false;
        readers.forEach(function (readFrame) {
          while (frame = readFrame()) loadingFrames.push(frame);
        });

        return loadingFrames;
      },
      'should return nothing when read': function (frames) {
        frames.should.be.empty;
      }
    },
  })
  .export(module)
