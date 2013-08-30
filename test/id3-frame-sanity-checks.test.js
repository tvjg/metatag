vows   = require('vows');
should = require('should');

ID3    = require('../lib/id3');
Parser = require('../lib/id3/parser');
F      = require('../lib/id3/frame');

Frame                = F.Frame;
TextFrame            = F.TextFrame;
NumericTextFrame     = F.NumericTextFrame;
NumericPartTextFrame = F.NumericPartTextFrame;

TPE1 = Frame.FRAMES.TPE1;
COMM = Frame.FRAMES.COMM;
TIT2 = Frame.FRAMES.TIT2;
TXXX = Frame.FRAMES.TXXX;

convert = require('../lib/text-encodings');
unsynch = require('../lib/id3/unsynch');

_22 = new ID3(); _22.version = { major: 2, minor: 2, sub: 0 }
_23 = new ID3(); _23.version = { major: 2, minor: 3, sub: 0 }
_24 = new ID3(); _24.version = { major: 2, minor: 4, sub: 0 }

// TT1 test framedata
_buff1           = new Buffer('54543100008300','hex');
_buff2           = new Buffer(Array(16).join('123456789abcdef'));
buff22DirectInts = Buffer.concat([_buff1, _buff2]);

// Unknown v2.2 framedata
unknownFrameData = new Buffer('58595A00000100','hex');

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
    'A TXXX frame initialized with {desc:\'d\', text:\'text\'}': {
      topic: new TXXX({desc:'d', text:'text'}),
      'should be an instance of TXXX': function (frame) {
        frame.should.be.an.instanceOf(TXXX);
      }
    },

    // Mutagen uses the rather cryptic test name test_22_uses_direct_ints. I
    // believe this relates to 2.2 using unpadded ints, but I'm not clear on
    // how exactly this relates to the provided test data.
    'A TT1 frame in a v2.2 tag': {
      topic: function () {
	var id3 = new ID3();
	id3.version = { major: 2, minor: 2, sub: 0 };

	var parser = new Parser(id3, {});

	var readFrame = parser.getFrameReader(buff22DirectInts, Frame.FRAMES_2_2);
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
	var parser24 = new Parser(_24, {});
	var parser23 = new Parser(_23, {});
	var parser22 = new Parser(_22, {});

	var readers = [
	  parser24.getFrameReader(new Buffer('012345678'), Frame.FRAMES),
	  parser23.getFrameReader(new Buffer('012345678'), Frame.FRAMES),
	  parser22.getFrameReader(new Buffer('01234'), Frame.FRAMES_2_2),
	  parser22.getFrameReader(new Buffer('545431000000','hex'), Frame.FRAMES_2_2)
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
    'An unknown v2.2 frame with a valid FrameID': {
      topic: function () {
	var readFrame = new Parser(_22, {}).getFrameReader(unknownFrameData, {});

	var loadingFrames = [], frame = false;
	while (frame = readFrame()) {
	  loadingFrames.push(frame);
	}

	return loadingFrames;
      },
      'should return the raw data': function (frames) {
	frames.should.eql([unknownFrameData]);
      }
    },
    'A TPE1 frame': {
      'passed the zlib compressed test data': {
	topic: function() {
	  var data = new Buffer('0000000f789c6328c9c82c5600a244fd92d4e21200267f0525','hex');
	  Frame.fromData(TPE1, _24, 0x9, data).nodeify(this.callback);
	},
	'should detect latin-1 encoding': function (err, frame) {
	  frame.encoding.should.eql(0);
	},
	'should decode text \'this is a/test\'': function (err, frame) {
	  frame.text.should.eql(['this is a/test']);
	}
      },
      'passed uncompressed data with a datalen flag': {
	topic: function() {
	  var data = new Buffer('0000000600412074657374','hex');
	  Frame.fromData(TPE1, _24, 0x01, data).nodeify(this.callback);
	},
	'should detect latin-1 encoding': function (err, frame) {
	  frame.encoding.should.eql(0);
	},
	'should decode text \'A test\'': function (err, frame) {
	  frame.text.should.eql(['A test']);
	}
      },
      'passed the data \'\\x03this is a test\'': {
	topic: function() {
	  var data = new Buffer('037468697320697320612074657374','hex');
	  return Frame.fromData(TPE1, _23, 0x00, data).nodeify(this.callback);
	},
	'should detect UTF8 encoding': function (err, frame) {
	  frame.encoding.should.eql(3);
	},
	'should decode text \'this is a test\'': function (err, frame) {
	  frame.text.should.eql(['this is a test']);
	}
      },
      'passed zlib compressed UTF16 data': {
	topic: function () {
	  return new Buffer('0000001f789c63fcffaf8421832193a19841014a2632e8339430a402d9250c0087c60723','hex');
	},
	'in a v2.3 tag': {
	  topic: function (data) {
	    return Frame.fromData(TPE1, _23, 0x80, data).nodeify(this.callback);
	  },
	  'should detect UTF16 encoding': function (err, frame) {
	    frame.encoding.should.eql(1);
	  },
	  'should decode text \'this is a/test\'': function (err, frame) {
	    frame.text.should.eql(['this is a/test']);
	  }
	},
	'in a v2.4 tag': {
	  topic: function (data) {
	    return Frame.fromData(TPE1, _24, 0x08, data).nodeify(this.callback);
	  },
	  'should detect UTF16 encoding': function (err, frame) {
	    frame.encoding.should.eql(1);
	  },
	  'should decode text \'this is a/test\'': function (err, frame) {
	    frame.text.should.eql(['this is a/test']);
	  }
	}
      }
    },
    'Unsynchronization decode passed': {
      '\'\\xff\\xff\\xff\\xff\'': {
	topic: new Buffer('ffffffff', 'hex'),
	'should throw a ValueError': function (data) {
	  (function () {
	    unsynch.decode(data);
	  }).should.throwError(/invalid sync-safe/);
	}
      },
      '\'\\xff\\xf0\\x0f\\x00\'': {
	topic: new Buffer('fff00f00', 'hex'),
	'should throw a ValueError': function (data) {
	  (function () {
	    unsynch.decode(data);
	  }).should.throwError(/invalid sync-safe/);
	}
      },
      '\'\\xff\\xe0\'': {
	topic: new Buffer('ffe0', 'hex'),
	'should throw a ValueError': function (data) {
	  (function () {
	    unsynch.decode(data);
	  }).should.throwError(/invalid sync-safe/);
	}
      },
      '\'\\xff\\x44\'': {
	topic: new Buffer('ff44', 'hex'),
	'should decode \'\\xff\\x44\'': function (data) {
	  unsynch.decode(data).should.eql(data);
	}
      }
    },
    'Standard TextFrames with differing text properties': {
      topic: new TIT2({text: 'a'}).HashKey,
      'should have the same HashKey': function (key) {
        key.should.equal(new TIT2({text: 'b'}).HashKey);
      }
    },
    'Two TXXX frames': {
      'with different text properties': {
	topic: new TXXX({text: 'a'}).HashKey,
	'should have the same HashKey': function (key) {
	  key.should.equal(new TXXX({text: 'b'}).HashKey);
	}
      },
      'with different descriptions': {
	topic: new TXXX({desc: 'a'}).HashKey,
	'should have differing HashKey properties': function (key) {
	  key.should.not.equal(new TXXX({desc: 'b'}).HashKey);
	}
      }
    },
    'Two COMM frames': {
      'with different text properties': {
	topic: new COMM({text: 'a'}).HashKey,
	'should have the same HashKey': function (key) {
	  key.should.equal(new COMM({text: 'b'}).HashKey);
	}
      },
      'with different descriptions': {
	topic: new COMM({desc: 'a'}).HashKey,
	'should have differing HashKey properties': function (key) {
	  key.should.not.equal(new COMM({desc: 'b'}).HashKey);
	}
      },
      'with different languages': {
	topic: new COMM({lang: 'abc'}).HashKey,
	'should have differing HashKey properties': function (key) {
	  key.should.not.equal(new COMM({lang: 'def'}).HashKey);
	}
      }
    }

    //TODO: Add remainder of frame sanity check tests
  })
  .export(module)
