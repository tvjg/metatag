var flatiron = require('flatiron');
var path     = require('path');
var util     = require('util');

var Metatag = require('./lib/metatag');
var app = module.exports = flatiron.app;

app.config.file({ file: path.join(__dirname, 'config', 'config.json') });

app.use(flatiron.plugins.cli, {
  usage: [
    , 'Usage: metatag [file or directory]'
    , 'Metatag will return an array of JSON objects with tag metadata.'
    , ''
    , '-h, --help   Prints this message'
  ],
  async: true
});

app.cmd(/(.+)/, function(filepath, next) {

  // Use promises or callbacks!
  new Metatag(filepath, function (err, tag) {
    if (err) {
      console.error(err.stack);
    } else {
      console.log(util.inspect(tag, { showHidden:true, depth: 3 }));
    }

    next();
  });

  //new Metatag()
    //.load(filepath)
    //.then(function (tag) {
      //console.log(util.inspect(tag, { showHidden:true, depth: 3 }));
    //})
    //.fail(function (err) {
      //console.error(err.stack);
    //})
    //.fin(next)
    //.done();
});

app.start();
