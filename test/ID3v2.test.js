var vows   = require('vows');
var should = require('should');
var path = require('path');
var fs = require('fs');

var ID3 = require('../lib/id3');

var silence = path.join('test','data','silence-44-s.mp3');

vows
  .describe('ID3v2')
  .addBatch({
    'An ID3 wrapper': {
      'loading a v2.3 tagged test file': {
        topic: new ID3(silence),
        'should have 8 keys': function (id3) {
          Object.keys(id3).length.should.eql(8);
        },
        'should have no unknown frames': function (id3) {
          id3.unknownFrames.should.be.empty;
        },
        'should read an album value of \'Quod Libet Test Data\'': function(id3) {
          should.equal(id3['TALB'], 'Quod Libet Test Data');
        },
        'should read a content type value of \'Silence\'': function(id3) {
          should.equal(id3['TCON'], 'Silence');
        },
        'should read a TIT1 value of \'Silence\'': function(id3) {
          should.equal(id3['TIT1'], 'Silence');
        },
        'should read a title value of \'Silence\'': function(id3) {
          should.equal(id3['TIT2'], 'Silence');
        },
        'should read a length of 3000': function(id3) {
          should.equal(id3['TLEN'], 3000);
        },
        'should not read an artist value of [\'piman\',\'jzig\']': function(id3) {
          id3.TPE1.text.should.not.eql(['piman','jzig']);
        },
        'should read a track string value of \'02/10\'': function(id3) {
          should.equal(id3['TRCK'].text, '02/10');
        },
        'should read a track value of 2': function(id3) {
          should.equal(id3['TRCK'], 2);
        },
        'should read a year value of \'2004\'': function(id3) {
          // TODO: Mutagen upgrades all tags to v2.4 on load which in this case
          // would transform TYER (which is present) to TDRC.
          should.equal(id3['TDRC'], '2004');
        }
      }
    }
  })
  .export(module);
