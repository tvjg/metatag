var vows   = require('vows');
var should = require('should');
var path = require('path');

var ID3 = require('../lib/id3');

var silence = path.join('test','data','silence-44-s-v1.mp3');

vows
  .describe('ID3v1')
  .addBatch({
    'An ID3 wrapper ': {
      'loading a v1.1 tagged test file ': {
        topic: function() {
          new ID3(silence, this.callback);
        },
        'should read an album value of \'Quod Libet Test Data\'': function(err, id3) {
          should.equal(id3['TALB'], 'Quod Libet Test Data');
        },
        'should read a genre value of \'Darkwave\'': function(err, id3) {
          should.equal(id3['TCON'].genres[0], 'Darkwave');
        },
        'should read a title value of \'Silence\'': function(err, id3) {
          should.equal(id3['TIT2'], 'Silence');
        },
        'should read an artist value of [\'piman\']': function(err, id3) {
          id3.TPE1.text.should.eql(['piman']);
        },
        'should read a track string value of \'2\'': function(err, id3) {
          should.equal(id3['TRCK'], '2');
        },
        'should read a track value of 2': function(err, id3) {
          should.equal(id3['TRCK'], 2);
        },
        'should read a year value of \'2004\'': function(err, id3) {
          should.equal(id3['TDRC'], '2004');
        }
      }
    }})
  .export(module);
