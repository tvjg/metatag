var vows   = require('vows');
var should = require('should');
var path = require('path');
var fs = require('fs');

var ID3 = require('../lib/id3');

var issue21 = path.join('test','data','issue_21.id3');

// Read more on this issue at
// https://code.google.com/p/mutagen/issues/detail?id=21
vows
  .describe('ID3 Issue 21')
  .addBatch({
    'An ID3 wrapper ': {
      'loading a file with an improper extended flag': {
        topic: function () {
	  new ID3(issue21, this.callback)
	},
        'should not set the extended flag': function (err, id3) {
          id3.f_extended.should.eql(false);
        },
        'should have TIT2 and TALB frames': function (err, id3) {
          id3.should.have.property('TIT2');
          id3.should.have.property('TALB');
        },
        'should have a properly decoded value for TIT2': function (err, id3) {
          should.equal(id3['TIT2'], 'Punk To Funk');
        }
      }
    }
  })
  .export(module);
