vows   = require('vows');
should = require('should');

Frame = require('../lib/id3/frame').Frame;
specs = require('../lib/id3/framespecs');

vows
  .describe('Spec Sanity Checks')
  .addBatch({
    'ByteSpec passed \'abcdefg\'': {
      topic: specs.ByteSpec('name'),

      'should read [97, \'bcdefg\']': function (s) {
        var res = s.read(null, new Buffer('abcdefg'));
	res.should.eql([97, new Buffer('bcdefg')]);
      }
    },
    'EncodingSpec': {
      topic: specs.EncodingSpec('name'),

      'passed \'abcdefg\'': {
        'should read [0, \'abcdefg\']': function (s) {
          var res = s.read(null, new Buffer('abcdefg'));
	  res.should.eql([0, new Buffer('abcdefg')]);
	}
      },
      'passed \'\\03abcdefg\'': {
        'should read [3, \'abcdefg\']': function (s) {
          var res = s.read(null, new Buffer('\x03abcdefg'))
	  res.should.eql([3, new Buffer('abcdefg')]);
	}
      },
    },
    'StringSpec passed \'abcdefg\'': {
      topic: specs.StringSpec('name', 3),

      'should read [\'abc\', \'defg\']': function (s) {
        var res = s.read(null, new Buffer('abcdefg'));
        res.should.eql(['abc', new Buffer('defg')]);
      }
    },
    'EncodedTextSpec passed \'abcd\\x00fg\'': {
      topic: specs.EncodedTextSpec('name'),

      'should read [\'abcd\', \'fg\']': function (s) {
        var f = new Frame(); f.encoding = 0;

        var res = s.read(f, new Buffer('abcd\x00fg'));
	res.should.eql(['abcd', new Buffer('fg')]);
      }
    },
    'TimeStampSpec': {
      topic: specs.TimeStampSpec('name'),

      'passed \'ab\\x00fg\'': {
        'should read [ ID3TimeStamp(\'ab\'), \'fg\']': function (s) {
          var f = new Frame(); f.encoding = 0;

          var res = s.read(f, new Buffer('ab\x00fg'));
          res.should.eql([ new specs.ID3TimeStamp('ab'), new Buffer('fg')]);
	}
      },
      'passed \'1234\\x00\'': {
        'should read [ ID3TimeStamp(\'1234\'), \'\']': function (s) {
          var f = new Frame(); f.encoding = 0;

          var res = s.read(f, new Buffer('1234\x00'));
          res.should.eql([ new specs.ID3TimeStamp('1234'), new Buffer('')]);
	}
      }
    }
    // TODO: Add BinaryDataSpec and VolumeAdjustmentSpec tests
  })
  .export(module);
