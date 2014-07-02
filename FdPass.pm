package FdPass;

use strict;
use warnings;

use Exporter;
use parent 'Exporter';
our @EXPORT_OK = qw(sendfd recvfd);

require XSLoader;
XSLoader::load('FdPass');

1;
