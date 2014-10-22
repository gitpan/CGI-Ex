package CGI::Ex::Conf;

### CGI Extended Conf Reader

###----------------------------------------------------------------###
#  Copyright 2003 - Paul Seamons                                     #
#  Distributed under the Perl Artistic License without warranty      #
###----------------------------------------------------------------###

### See perldoc at bottom

use strict;
use vars qw($VERSION 
            @DEFAULT_PATHS
            $DEFAULT_EXT
            %EXT_READERS
            $DIRECTIVE
            $IMMUTABLE_QR
            $IMMUTABLE_KEY
            %CACHE
            $HTML_KEY
            );
use CGI::Ex::Dump qw(debug);

$VERSION = '0.2';

$DEFAULT_EXT = 'conf';

%EXT_READERS = (''         => \&read_handler_yaml,
                'conf'     => \&read_handler_yaml,
                'ini'      => \&read_handler_ini,
                'pl'       => \&read_handler_pl,
                'sto'      => \&read_handler_storable,
                'storable' => \&read_handler_storable,
                'val'      => \&read_handler_yaml,
                'xml'      => \&read_handler_xml,
                'yaml'     => \&read_handler_yaml,
                'yml'      => \&read_handler_yaml,
                'html'     => \&read_handler_html,
                'htm'      => \&read_handler_html,
                );

### $DIRECTIVE controls how files are looked for.
### If directories 1, 2 and 3 are passed and each has a config file
### LAST would return 3, FIRST would return 1, and MERGE will
### try to put them all together.  Merge behavior of hashes
### is determined by $IMMUTABLE_\w+ variables.
$DIRECTIVE = 'LAST'; # LAST, MERGE, FIRST

$IMMUTABLE_QR = qr/_immu(?:table)?$/i;

$IMMUTABLE_KEY = 'immutable';

###----------------------------------------------------------------###

sub new {
  my $class = shift || __PACKAGE__;
  my $self  = (@_ && ref($_[0])) ? shift : {@_}; 

  return bless $self, $class;
}

sub paths {
  my $self = shift;
  return $self->{paths} ||= \@DEFAULT_PATHS;
}

sub read_ref {
  my $self = shift;
  my $file = shift;
  my $args = shift || {};
  my $ext;

  ### they passed the right stuff already
  if (ref $file) {
    return $file;

  ### if contains a newline - treat it as a YAML string
  } elsif (index($file,"\n") != -1) {
    return &yaml_load($file);

  ### otherwise base it off of the file extension
  } elsif ($args->{file_type}) {
    $ext = $args->{file_type};
  } elsif ($file =~ /\.(\w+)$/) {
    $ext = $1;
  } else {
    $ext = defined($args->{default_ext}) ? $args->{default_ext}
      : defined($self->{default_ext}) ? $self->{default_ext}
      : defined($DEFAULT_EXT) ? $DEFAULT_EXT : '';
    $file = length($ext) ? "$file.$ext" : $file;
  }

  ### allow for a pre-cached reference
  if (exists $CACHE{$file} && ! $self->{no_cache}) {
    return $CACHE{$file};
  }

  ### determine the handler
  my $handler;
  if ($args->{handler}) {
    $handler = (UNIVERSAL::isa($args->{handler},'CODE'))
      ? $args->{handler} : $args->{handler}->{$ext};
  } elsif ($self->{handler}) {
    $handler = (UNIVERSAL::isa($self->{handler},'CODE'))
      ? $self->{handler} : $self->{handler}->{$ext};
  }
  if (! $handler) {
    $handler = $EXT_READERS{$ext} || die "Unknown file extension: $ext";
  }

  return eval { scalar &$handler($file, $self, $args) };
}

### allow for different kinds of merging of arguments
### allow for key fallback on hashes
### allow for immutable values on hashes
sub read {
  my $self      = shift;
  my $namespace = shift;
  my $args      = shift || {};
  my $REF       = $args->{ref} || undef;    # can pass in existing set of options
  my $IMMUTABLE = $args->{immutable} || {}; # can pass existing immutable types

  $self = $self->new() if ! ref $self;

  ### allow for fast short ciruit on path lookup for several cases
  my $directive;
  my @paths = ();
  if (ref($namespace)                   # already a ref
      || index($namespace,"\n") != -1   # yaml string to read in
      || $namespace =~ m|^\.{0,2}/.+$|  # absolute or relative file
      ) {
    push @paths, $namespace;
    $directive = 'FIRST';

  ### use the default directories
  } else {
    $directive = uc($args->{directive} || $self->{directive} || $DIRECTIVE);
    $namespace =~ s|::|/|g;  # allow perlish style namespace
    my $paths = $args->{paths} || $self->paths
      || die "No paths found during read on $namespace";
    $paths = [$paths] if ! ref $paths;
    if ($directive eq 'LAST') { # LAST shall be FIRST
      $directive = 'FIRST';
      $paths = [reverse @$paths] if $#$paths != 0;
    }
    foreach my $path (@$paths) {
      next if exists $CACHE{$path} && ! $CACHE{$path};
      push @paths, "$path/$namespace";
    }
  }

  ### make sure we have at least one path
  if ($#paths == -1) {
    die "Couldn't find a path for namespace $namespace.  Perhaps you need to pass paths => \@paths";
  }
  
  ### now loop looking for a ref
  foreach my $path (@paths) {
    my $ref = $self->read_ref($path, $args) || next;
    if (! $REF) {
      if (UNIVERSAL::isa($ref, 'ARRAY')) {
        $REF = [];
      } elsif (UNIVERSAL::isa($ref, 'HASH')) {
        $REF = {};
      } else {
        die "Unknown config type of \"".ref($ref)."\" for namespace $namespace";
      }
    } elsif (! UNIVERSAL::isa($ref, ref($REF))) {
      die "Found different reference types for namespace $namespace"
        . " - wanted a type ".ref($REF);
    }
    if (ref($REF) eq 'ARRAY') {
      if ($directive eq 'MERGE') {
        push @$REF, @$ref;
        next;
      }
      splice @$REF, 0, $#$REF + 1, @$ref;
      last;
    } else {
      my $immutable = delete $ref->{$IMMUTABLE_KEY};
      my ($key,$val);
      if ($directive eq 'MERGE') {
        while (($key,$val) = each %$ref) {
          next if $IMMUTABLE->{$key};
          my $immute = $key =~ s/$IMMUTABLE_QR//o;
          $IMMUTABLE->{$key} = 1 if $immute || $immutable;
          $REF->{$key} = $val;
        }
        next;
      }
      delete $REF->{$key} while $key = each %$REF;
      while (($key,$val) = each %$ref) {
        my $immute = $key =~ s/$IMMUTABLE_QR//o;
        $IMMUTABLE->{$key} = 1 if $immute || $immutable;
        $REF->{$key} = $val;
      }
      last;
    }
  }
  $REF->{"Immutable Keys"} = $IMMUTABLE if scalar keys %$IMMUTABLE;
  return $REF;
}

###----------------------------------------------------------------###

sub read_handler_ini {
  my $file = shift;
  require Config::IniHash;
  return &Config::IniHash::ReadINI($file);
}

sub read_handler_pl {
  my $file = shift;
  ### do has odd behavior in that it turns a simple hashref
  ### into hash - help it out a little bit
  my @ref = do $file;
  return ($#ref != 0) ? {@ref} : $ref[0];
}

sub read_handler_storable {
  my $file = shift;
  require Storable;
  return &Storable::retrieve($file);
}

sub read_handler_yaml {
  my $file = shift;
  local $/ = undef;
  local *IN;
  open (IN,$file) || die "Couldn't open $file: $!";
  my $text = <IN>;
  close IN;
  return &yaml_load($text);
}

sub yaml_load {
  my $text = shift;
  require YAML;
  my @ret = eval { &YAML::Load($text) };
  if ($@) {
    die "$@";
  }
  return ($#ret == 0) ? $ret[0] : \@ret;
}

sub read_handler_xml {
  my $file = shift;
  require XML::Simple;
  return XML::Simple::XMLin($file);
}

### this handler will only function if a html_key (such as validation)
### is specified - actually this somewhat specific to validation - but
### I left it as a general use for other types

### is specified
sub read_handler_html {
  my $file = shift;
  my $self = shift;
  my $args = shift;
  my $key = $args->{html_key} || $self->{html_key} || $HTML_KEY;
  return undef if ! $key || $key !~ /^\w+$/;
  return undef if ! eval {require YAML};

  ### get the html
  my $html = '';
  local *IN;
  open(IN, $file) || return undef;
  CORE::read(IN, $html, -s $file);
  close IN;

  my $str = '';
  my @order = ();
  while ($html =~ m{
    (document\.    # global javascript
     | var\s+      # local javascript
     | <\w+\s+[^>]*?) # input, form, select, textarea tag
      \Q$key\E   # the key
      \s*=\s*    # an equals sign
      ([\"\'])   # open quote
      (.+?[^\\]) # something in between
      \2        # close quote
    }xsg) {
    my ($line, $quot, $yaml) = ($1, $2, $3);
    if ($line =~ /^(document\.|var\s)/) { # js variable
      $yaml =~ s/\\$quot/$quot/g;
      $yaml =~ s/\\n\\\n?/\n/g;
      $yaml =~ s/\\\\/\\/g;
      $yaml =~ s/\s*$/\n/s; # fix trailing newline
      $str = $yaml; # use last one found
    } else { # inline attributes
      $yaml =~ s/\s*$/\n/s; # fix trailing newline
      if ($line =~ m/<form/i) {
        $yaml =~ s/^\Q$1\E//m if $yaml =~ m/^( +)/s;
        $str .= $yaml;

      } elsif ($line =~ m/\bname\s*=\s*('[^\']*'|"[^\"]*"|\S+)/) {
        my $key = $1;
        push @order, $key;
        $yaml =~ s/^/ /mg; # indent entire thing
        $yaml =~ s/^(\ *[^\s&*\{\[])/\n$1/; # add first newline
        $str .= "$key:$yaml";
      }
    }
  }
  $str .= "group order: [".join(", ",@order)."]\n"
    if $str && $#order != -1 && $key eq 'validation';

  return undef if ! $str;
  my $ref = eval {&yaml_load($str)};
  if ($@) {
    my $err = "$@";
    if ($err =~ /line:\s+(\d+)/) {
      my $line = $1;
      while ($str =~ m/(.+)/gm) {
        next if -- $line;
        $err .= "LINE = \"$1\"\n";
        last;
      }
    }
    debug $err;
    die $err;
  }
  return $ref;
}

###----------------------------------------------------------------###

sub preload_files {
  my $self  = shift;
  my $paths = shift || $self->paths;
  require File::Find;

  ### what extensions do we look for
  my %EXT;
  if ($self->{handler}) {
    if (UNIVERSAL::isa($self->{handler},'HASH')) {
      %EXT = %{ $self->{handler} };
    }
  } else {
    %EXT = %EXT_READERS;
    if (! $self->{html_key} && ! $HTML_KEY) {
      delete $EXT{$_} foreach qw(html htm);
    }
  }
  return if ! keys %EXT;
  
  ### look in the paths for the files
  foreach my $path (ref($paths) ? @$paths : $paths) {
    $path =~ s|//+|/|g;
    $path =~ s|/$||;
    next if exists $CACHE{$path};
    if (-f $path) {
      my $ext = ($path =~ /\.(\w+)$/) ? $1 : '';
      next if ! $EXT{$ext};
      $CACHE{$path} = $self->read($path);
    } elsif (-d _) {
      $CACHE{$path} = 1;
      &File::Find::find(sub {
        return if exists $CACHE{$File::Find::name};
        return if $File::Find::name =~ m|/CVS/|;
        return if ! -f;
        my $ext = (/\.(\w+)$/) ? $1 : '';
        return if ! $EXT{$ext};
        $CACHE{$File::Find::name} = $self->read($File::Find::name);
      }, "$path/");
    } else {
      $CACHE{$path} = 0;
    }
  }
}

###----------------------------------------------------------------###

1;

__END__

=head1 NAME

CGI::Ex::Conf - CGI Extended Conf Reader

=head1 SYNOPSIS

  my $cob = CGI::Ex::Conf->new;
  
  my $full_path_to_file = "/tmp/foo.val"; # supports ini, sto, val, pl, xml
  my $hash = $cob->read($file);

  local $cob->{default_ext} = 'conf'; # default anyway

  
  my @paths = qw(/tmp, /home/pauls);
  local $cob->{paths} = \@paths;
  my $hash = $cob->read('My::NameSpace');
  # will look in /tmp/My/NameSpace.conf and /home/pauls/My/NameSpace.conf
  
  my $hash = $cob->read('My::NameSpace', {paths => ['/tmp']});
  # will look in /tmp/My/NameSpace.conf

  
  local $cob->{directive} = 'MERGE';
  my $hash = $cob->read('FooSpace');
  # OR #
  my $hash = $cob->read('FooSpace', {directive => 'MERGE'});
  # will return merged hashes from /tmp/FooSpace.conf and /home/pauls/FooSpace.conf
  # immutable keys are preserved from originating files

  
  local $cob->{directive} = 'FIRST';
  my $hash = $cob->read('FooSpace');
  # will return values from first found file in the path.

  
  local $cob->{directive} = 'LAST'; # default behavior
  my $hash = $cob->read('FooSpace');
  # will return values from last found file in the path.
  
=head1 DESCRIPTION

There are half a million Conf readers out there.  Why not add one more.
Actually, this module provides a wrapper around the many file formats
and the config modules that can handle them.  It does not introduce any
formats of its own.

This module also provides a preload ability which is useful in conjunction
with mod_perl.

=head1 METHODS

=over 4

=item C<-E<gt>read>

First argument may be either a perl data structure, yaml string, a
full filename, or a file "namespace".

The second argument can be a hashref of override values (referred to
as $args below)..

If the first argument is a perl data structure, it will be
copied one level deep and returned (nested structures will contain the
same references).  A yaml string will be parsed and returned.  A full
filename will be read using the appropriate handler and returned (a
file beginning with a / or ./ or ../ is considered to be a full
filename).  A file "namespace" (ie "footer" or "my::config" or
"what/ever") will be turned into a filename by looking for that
namespace in the paths found either in $args->{paths} or in
$self->{paths} or in @DEFAULT_PATHS.  @DEFAULT_PATHS is empty by
default as is $self->{paths} - read makes no attempt to guess what
directories to look in.  If the namespace has no extension the
extension listed in $args->{default_ext} or $self->{default_ext} or
$DEFAULT_EXT will be used).

  my $ref = $cob->read('My::NameSpace', {
    paths => [qw(/tmp /usr/data)],
    default_ext => 'pl',
  });
  # would look first for /tmp/My/NameSpace.pl
  # and then /usr/data/My/NameSpace.pl

  my $ref = $cob->read('foo.sto', {
    paths => [qw(/tmp /usr/data)],
    default_ext => 'pl',
  });
  # would look first for /tmp/foo.sto
  # and then /usr/data/foo.sto

When a namespace is used and there are multiple possible paths, there
area a few options to control which file to look for.  A directive of
'FIRST', 'MERGE', or 'LAST' may be specified in $args->{directive} or
$self->{directive} or the default value in $DIRECTIVE will be used
(default is 'LAST'). When 'FIRST' is specified the first path that
contains the namespace is returned.  If 'LAST' is used, the last
found path that contains the namespace is returned.  If 'MERGE' is
used, the data structures are joined together.  If they are
arrayrefs, they are joined into one large arrayref.  If they are
hashes, they are layered on top of each other with keys found in later
paths overwriting those found in earlier paths.  This allows for
setting system defaults in a root file, and then allow users to have
custom overrides.

It is possible to make keys in a root file be immutable (non
overwritable) by adding a suffix of _immutable or _immu to the key (ie
{foo_immutable => 'bar'}).  If a value is found in the file that
matches $IMMUTABLE_KEY, the entire file is considered immutable.
The immutable defaults may be overriden using $IMMUTABLE_QR and $IMMUTABLE_KEY.

=item C<-E<gt>preload_files>

Arguments are file(s) and/or directory(s) to preload.  preload_files will
loop through the arguments, find the files that exist, read them in using
the handler which matches the files extension, and cache them by filename
in %CACHE.  Directories are spidered for file extensions which match those
listed in %EXT_READERS.  This is useful for a server environment where CPU
may be more precious than memory.

=head1 FILETYPES

CGI::Ex::Conf supports the files found in %EXT_READERS by default.
Additional types may be added to %EXT_READERS, or a custom handler may be
passed via $args->{handler} or $self->{handler}.  If the custom handler is
a code ref, all files will be passed to it.  If it is a hashref, it should
contain keys which are extensions it supports, and values which read those
extensions.

Some file types have benefits over others.  Storable is very fast, but is
binary and not human readable.  YAML is readable but very slow.  I would
suggest using a readable format such as YAML and then using preload_files
to load in what you need at run time.  All preloaded files are faster than
any of the other types.

The following is the list of handlers that ships with CGI::Ex::Conf (they
will only work if the supporting module is installed on your system):

=over 4

=item C<pl>

Should be a file containing a perl structure which is the last thing returned.

=item C<sto> and C<storable>

Should be a file containing a structure stored in Storable format.
See L<Storable>.

=item C<yaml> and C<conf> and C<val>

Should be a file containing a yaml document.  Multiple documents are returned
as a single arrayref.  Also - any file without an extension and custom handler
will be read using YAML.  See L<YAML>.

=item C<ini>

Should be a windows style ini file.  See L<Config::IniHash>

=item C<xml>

Should be an xml file.  It will be read in by XMLin.  See L<XML::Simple>.

=item C<html> and C<htm>

This is actually a custom type intended for use with CGI::Ex::Validate.
The configuration to be read is actually validation that is stored
inline with the html.  The handler will look for any form elements or
input elements with an attribute with the same name as in $HTML_KEY.  It
will also look for a javascript variable by the same name as in $HTML_KEY.
All configuration items done this way should be written in YAML.
For example, if $HTML_KEY contained 'validation' it would find validation in:

  <input type=text name=username validation="{required: 1}">
  # automatically indented and "username:\n" prepended
  # AND #
  <form name=foo validation="
  general no_confirm: 1
  ">
  # AND #
  <script>
  document.validation = "\n\
  username: {required: 1}\n\
  ";
  </script>
  # AND #
  <script>
  var validation = "\n\
  username: {required: 1}\n\
  ";
  </script>

If the key $HTML_KEY is not set, the handler will always return undef
without even opening the file.

=back

=head1 TODO

Make a similar write method that handles immutability.

=head1 AUTHOR

Paul Seamons

=head1 LICENSE

This module may be distributed under the same terms as Perl itself.

=cut

