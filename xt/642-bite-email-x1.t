use strict;
use warnings;
use Test::More;
use lib qw(./lib ./blib/lib);
require './t/600-lhost-code';

my $enginename = 'X1';
my $samplepath = sprintf("./set-of-emails/private/email-%s", lc $enginename);
my $enginetest = Sisimai::Lhost::Code->maketest;
my $isexpected = [
    { 'n' => '01001', 'r' => qr/filtered/ },
    { 'n' => '01002', 'r' => qr/filtered/ },
    { 'n' => '01003', 'r' => qr/filtered/ },
    { 'n' => '01004', 'r' => qr/filtered/ },
    { 'n' => '01005', 'r' => qr/filtered/ },
];

plan 'skip_all', sprintf("%s not found", $samplepath) unless -d $samplepath;
$enginetest->($enginename, $isexpected, 1, 0);
done_testing;

