var vows   = require('vows');
var should = require('should');
var path = require('path');
var sprintf = require("sprintf-js").sprintf

var ID3 = require('../lib/id3');
var TCON = require('../lib/id3/frame').FRAMES.TCON;
var GENRES = require('../lib/id3/constants').GENRES;

function _g(s) {
  var frame = new TCON({ text:s });
  return frame.genres;
}

vows
  .describe('ID3 Genre')
  .addBatch({
    'A TCON frame': {
      'with an empty text property': {
        topic: _g(''),
        'should report no genres': function(genres) {
          genres.should.eql([]);
        }
      },
      'loading any known ID3v1 genre by number': {
        topic: function() {
          genres = []
          for (var i = 0; i < GENRES.length; i++) {
            g = _g(sprintf("%02d", i));
            genres.push(g);
          }
          return genres; 
        },
        'should find find a match in the genres list': function(genres) {
          for (var i = 0; i < GENRES.length; i++) {
            genres[i].should.eql([ GENRES[i] ]);
          }
        }
      },
      'loading any known ID3v1 genre by parened number': {
        topic: function() {
          genres = []
          for (var i = 0; i < GENRES.length; i++) {
            g = _g(sprintf("(%02d)", i));
            genres.push(g);
          }
          return genres; 
        },
        'should find find a match in the genres list': function(genres) {
          for (var i = 0; i < GENRES.length; i++) {
            genres[i].should.eql([ GENRES[i] ]);
          }
        }
      },
      'whose text property is set to \'(255)\'': {
        topic: _g('(255)'),
        'should report \'Unknown\' genre': function(genres) {
          genres.should.eql(['Unknown']);
        }
      },
      'whose text property is set to a genre number beyond the bounds of the ID3v1 genres list': {
        topic: _g('(199)'),
        'should report \'Unknown\' genre': function(genres) {
          genres.should.eql(['Unknown']);
        }
      },
      'whose text property is set to \'(00)(02)\'': {
        topic: _g('(00)(02)'),
        'should report [\'Blues\',\'Country\'] genres': function(genres) {
          genres.should.eql(['Blues','Country']);
        }
      },
      'whose text property contains CR, (CR), RX, or (RX)': {
        topic: [ _g('CR'), _g('(CR)'),  _g('RX'), _g('(RX)') ],
        'should appropriately add cover or remix to the genres': function(results) {
          results.should.eql([ ['Cover'], ['Cover'], ['Remix'], ['Remix'] ]);
        }
      },
      'whose text property contains (00)(02)Real Folk Blues': {
        topic: _g('(00)(02)Real Folk Blues'),
        'should report [\'Blues\',\'Country\',\'Real Folk Blues\'] as genres': function(genres) {
          genres.should.eql(['Blues','Country','Real Folk Blues']);
        }
      },
      'whose text property contains consecutive double left parens': {
        topic: [ _g('(0)((A genre)'), _g('(10)((20)') ],
        'should escape to single left paren and treat as text': function(results) {
          results[0].should.eql(['Blues', '(A genre)']);
          results[1].should.eql(['New Age','(20)']);
        }
      },
      'whose text property contains a null character': {
        topic: _g('0\x00A genre'),
        'should treat it as a genre separator': function(genres) {
          genres.should.eql(['Blues','A genre']);
        }
      },
      'whose text property begins with null character': {
        topic: _g('\x000\x00A genre'),
        'should ignore the empty genre': function(genres) {
          genres.should.eql(['Blues','A genre']);
        }
      },
      'whose text property contains a complicated combination of the above ': {
        topic: _g('(20)(CR)\x0030\x00\x00Another\x00(51)Hooray'),
        'should not balk': function(genres) {
          genres.should.eql(['Alternative', 'Cover', 'Fusion', 'Another','Techno-Industrial', 'Hooray']);
        }
      },
      'whose text property contains a repeated genre separated by a null character': {
        topic: [ _g('(20)Alternative'), _g('(20)\x00Alternative') ],
        'should report the same genre twice': function(results) {
          results.should.eql([ ['Alternative'], ['Alternative','Alternative'] ]);
        }
      },
      'whose genres property is set to [\'a genre\',\'another\']': {
        topic: function() {
          var frame = new TCON({ encoding:0,text:'' });
          frame.genres = ['a genre','another'];
          return frame;
        },
        'should report [\'a genre\',\'another\'] as genres': function(frame) {
          frame.genres.should.eql(['a genre','another']);
        }
      }
    }
  })
  .export(module);
