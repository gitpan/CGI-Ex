#!perl -T
# -*- Mode: Perl; -*-

=head1 NAME

1_validate_14_untaint.t - Test CGI::Ex::Validate's ability to untaint tested fields

=cut

use strict;
use Test::More tests => 14;
use FindBin qw($Bin);
use lib ($Bin =~ /(.+)/ ? "$1/../lib" : ''); # add bin - but untaint it

### Set up taint checking
sub is_tainted { local $^W = 0; ! eval { eval("#" . substr(join("", @_), 0, 0)); 1; 0 } }

SKIP: {

my $taint = join(",", $0, %ENV, @ARGV);
if (! is_tainted($taint) && open(my $fh, "/dev/urandom")) {
  sysread($fh, $taint, 1);
}
$taint = substr($taint, 0, 0);
if (! is_tainted($taint)) {
    skip("is_tainted doesn't appear to work", 14);
}

### make sure tainted hash values don't bleed into other values
my $form = {};
$form->{'foo'} = "123$taint";
$form->{'bar'} = "456$taint";
$form->{'baz'} = "789";
if (!  is_tainted($form->{'foo'})) {
    skip("Tainted hash key didn't work right", 14);
} elsif (is_tainted($form->{'baz'})) {
    # untaint checking doesn't really work
    skip("Hashes with mixed taint don't work right", 14);
}

###----------------------------------------------------------------###
### Looks good - here we go

use_ok('CGI::Ex::Validate');

my $e;

ok(is_tainted($taint));
ok(is_tainted($form->{'foo'}));
ok(! is_tainted($form->{'baz'}));
ok(! is_tainted($form->{'non_existent_key'}));

sub validate { scalar CGI::Ex::Validate::validate(@_) }


###----------------------------------------------------------------###

$e = validate($form, {
  foo => {
    match   => 'm/^\d+$/',
    untaint => 1,
  },
});

ok(! $e);
ok(! is_tainted($form->{foo}));

###----------------------------------------------------------------###

$e = validate($form, {
  bar => {
    match   => 'm/^\d+$/',
  },
});

ok(! $e);
ok(is_tainted($form->{bar}));

###----------------------------------------------------------------###

$e = validate($form, {
  bar => {
    untaint => 1,
  },
});

ok($e);
#print $e if $e;
ok(is_tainted($form->{bar}));

###----------------------------------------------------------------###

ok(!is_tainted($form->{foo}));
ok( is_tainted($form->{bar}));
ok(!is_tainted($form->{baz}));

}
