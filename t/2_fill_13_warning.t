# -*- Mode: Perl; -*-

#!/usr/bin/perl -w

# emits warnings for HTML::FIF <= 0.22

use CGI qw(:no_debug);
use CGI::Ex;
use Test;

BEGIN { plan tests => 1 }

local $/;
my $html = qq{<input type="submit" value="Commit">};
 
my $q = new CGI;
 
$q->param( "name", "John Smith" );
my $fif = new CGI::Ex;
my $output = $fif->fill(
                         scalarref => \$html,
                         fobject   => $q
);

ok($html =~ m!<input( type="submit"| value="Commit"){2}>!);
