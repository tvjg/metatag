var vows   = require('vows');
var should = require('should');

var BitPaddedInt = require('../lib/bit-padded-int.js');

vows.describe('BitPaddedInt').addBatch({
  'A BitPaddedInt(0)': {
    topic: BitPaddedInt('\x00\x00\x00\x00'),
    'should be equal to 0': function(bpi) {
      bpi.should.equal(0);
    }
  },
  'A BitPaddedInt(1)': {
    topic: BitPaddedInt('\x00\x00\x00\x01'),
    'should be equal to 1': function(bpi) {
      bpi.should.equal(1);
    }
  },
  'A BitPaddedInt(129)': {
    topic: BitPaddedInt('\x00\x00\x01\x01'),
    'should be equal to 0x81': function(bpi) {
      bpi.should.equal(0x81);
    }
  },
  'A BitPaddedInt(129b)': {
    topic: BitPaddedInt('\x00\x00\x01\x81'),
    'should be equal to 0x81': function(bpi) {
      bpi.should.equal(0x81);
    }
  },
  'A BitPaddedInt(65, 6)': {
    topic: BitPaddedInt('\x00\x00\x01\x81', 6),
    'should be equal to 0x41': function(bpi) {
      bpi.should.equal(0x41);
    }
  },
  'A BitPaddedInt(32b, 8)': {
    topic: BitPaddedInt('\xFF\xFF\xFF\xFF', 8),
    'should be equal to 0xFFFFFFFF': function(bpi) {
      bpi.should.equal(0xFFFFFFFF);
    }
  },
}).export(module);
