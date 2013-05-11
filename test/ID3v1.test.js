var vows   = require('vows');
var should = require('should');
var path = require('path');

var ID3 = require('../lib/ID3');

var silence = path.join('test','data','silence-44-s-v1.mp3');

vows
  .describe('ID3v1 Loading')
  .addBatch({
    'An ID3 wrapper ': {
      'loading a v1.1 tag ': {
        topic: function() {
          return new ID3(silence);
        },
        'should read an album value of \'Quod Libet Test Data\'': function(id3) {
          should.equal(id3['TALB'], 'Quod Libet Test Data');
        },
        'should read a title value of \'Silence\'': function(id3) {
          should.equal(id3['TIT2'], 'Silence');
        },
        //TODO: This tests for ['piman'] in mutagen test. Why?
        'should read a artist value of \'piman\'': function(id3) {
          should.equal(id3['TPE1'], 'piman');
        }
      }
    }})
  .export(module);
